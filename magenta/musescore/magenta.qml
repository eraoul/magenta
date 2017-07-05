// Copyright 2016 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////////

import QtQuick 2.0
import MuseScore 1.0

MuseScore {
      version:  "1.0"
      description: "This plugin connects to a Magenta server to generate music for the selected region"
      menuPath: "Plugins.Magenta"

      function keySignatureIdToMajorEnumString(id) {
        switch(id) {
          case -7:
            return 'B';
          case -6:
            return 'G_FLAT';
          case -5:
            return 'D_FLAT';
          case -4:
            return 'A_FLAT';
          case -3:
            return 'E_FLAT';
          case -2:
            return 'B_FLAT';
          case -1:
            return 'F';
          case 0:
            return 'C';
          case 1:
            return 'G';
          case 2:
            return 'D';
          case 3:
            return 'A';
          case 4:
            return 'E';
          case 5:
            return 'B';
          case 6:
            return 'F_SHARP';
          case 7:
            return 'C_SHARP';
          default:
            console.log('Unknown key signature: ' + id);
            Qt.quit();
        }
      }

      function getPartNumber(midiParts, track) {
        console.log(midiParts);
        //for (var i = 0; i < midiParts.length; i++) {
        for (var i in midiParts) {
          console.log("Part " + i)
          var part = midiParts[i];
          if (track >= part.startTrack && track < part.endTrack) {
            return i;
          }
        }
        console.error("Track " + track + " not found in midiParts");
      }

      function createNoteSequence() {
        var noteSequence = {
          timeSignatures: [],
          keySignatures: [],
          // Hard code this until the annotations bug is fixed:
          // https://musescore.org/en/node/115971
          tempos: [
            {
              time: 0,
              bpm: 120,
            }
          ],
          notes: [],
          totalTime: curScore.duration,
          sourceInfo: {
            sourceType: 'SCORE',
            sourceName: 'MuseScore Plugin',
          },
          ticksPerBeat: 220,
          partInfos: [],
        };

        // Find labels and MIDI channel/program information for each part.
        var midiParts = {};
        for (var i = 0; i < curScore.parts.length; i++) {
          var part = curScore.parts[i];
          if (part) {
            noteSequence.partInfos.push({
              part: i,
              name: part.partName,
            });
            midiParts[i] = {
              midiChannel: part.midiChannel,
              midiProgram: part.midiProgram,
              startTrack: part.startTrack,
              endTrack: part.endTrack,
            }
            console.log("Midi: part " + i + "(tracks " + part.startTrack + "-" + (part.endTrack-1)
              + ") = " + part.partName + "  channel = " + part.midiChannel + " program = "
              + part.midiProgram);
          }
        }
        // Find all time signatures.
        // TODO: Directly insert these into noteSequence once we can calculate
        // the time from the tick: https://musescore.org/en/node/117611
        var timeSignatures = [];
        for(var seg = curScore.firstSegment(); !!seg; seg = seg.next) {
          for (var track = 0; track < curScore.ntracks; ++track) {
            var elem = seg.elementAt(track);
            if (!elem) {
              continue;
            }
            if (elem.type == Element.TIMESIG) {
              // TODO: handle global vs local time signatures.
              var timeSignature = {
                tick: seg.tick,
                numerator: elem.numerator,
                denominator: elem.denominator,
              };
              timeSignatures.push(timeSignature);
            }
          }
        }

        var cursor = curScore.newCursor();
        for (var staff = 0; staff < curScore.nstaves; staff++) {
          for (var voice = 0; voice < 4; voice++) {
            console.log("Staff " + staff + " voice " + voice);

            cursor.voice = voice;
            cursor.staffIdx = staff;
            cursor.rewind(0); // beginning of score

            for (; cursor.segment; cursor.next()) {
              console.log("Cursor at " + cursor.tick);
              // Extract any relevant time signatures
              while(timeSignatures.length &&
                  timeSignatures[0].tick <= cursor.tick) {
                var tickSignature = timeSignatures.shift();
                noteSequence.timeSignatures.push({
                  time: cursor.time / 1000.0,
                  numerator: tickSignature.numerator,
                  denominator: tickSignature.denominator,
                });
              }

              // TODO: directly extract key signatures from segments once key
              // signature access works: https://musescore.org/en/node/100501
              var keyEnum = keySignatureIdToMajorEnumString(
                  cursor.keySignature);
              var lastKeySigEnum;
              if (noteSequence.keySignatures.length) {
                lastKeySigEnum = noteSequence.keySignatures[
                    noteSequence.keySignatures.length - 1].key;
              }
              if (keyEnum != lastKeySigEnum) {
                noteSequence.keySignatures.push({
                  time: cursor.time / 1000.0,
                  key: keyEnum,
                  // We don't know what mode we're in. Just assume major. The
                  // import information is how many sharps/flats.
                  mode: 'MAJOR',
                });
              }
              console.log("HERE");
              if (!cursor.element) {
                continue;
              }

              var elem = cursor.element;
              console.log("Element: " + elem.userName());
              if (elem.type == Element.CHORD) {
                // TODO: gracenotes
                for (var i = 0; i < elem.notes.length; i++) {
                  var scoreNote = elem.notes[i];
                  // duration = globalDuration.ticks /
                  //   480 (musescore ticks per quarter note) *
                  //   tempo (seconds per quarter note)
                  // globalDuration accounts for tuplets. duration does not.
                  var durationSeconds =
                      elem.globalDuration.ticks / 480 * cursor.tempo;

                  var nsNote = {};
                  nsNote.pitch = scoreNote.ppitch;
                  nsNote.velocity = 127;
                  nsNote.startTime = cursor.time / 1000.0;
                  nsNote.endTime = nsNote.startTime + durationSeconds;
                  //nsNote.part = (staff * 4) + voice;
                  track = (staff * 4) + voice;
                  nsNote.part = getPartNumber(midiParts, track);
                  nsNote.instrument = midiParts[nsNote.part].midiChannel;
                  nsNote.program = midiParts[nsNote.part].midiProgram;
                  noteSequence.notes.push(nsNote);
                }
              }
            }
          }
        }

        return noteSequence;
      }

      function createFillParameter() {
        var cursor = curScore.newCursor();
        cursor.rewind(1);
        if (!cursor.segment) { // no selection
          return {
            startTime: 0,
            endTime: curScore.duration,
            firstPart: 0,
            lastPart: curScore.ntracks - 1,
          };
        } else {
           var startTime = cursor.time / 1000.0;
           var firstPart = cursor.track;
           cursor.rewind(2);
           var endTime = cursor.time / 1000.0;
           // endTime could be 0 if the user selects the end of the track.
           if (endTime == 0) {
             endTime = curScore.duration;
           }
           var lastPart = cursor.track;

           return {
             startTime: startTime,
             endTime: endTime,
             firstPart: firstPart,
             lastPart: lastPart,
           };
        }
      }

      function createAutoFillRequest() {
        return {
          noteSequence: createNoteSequence(),
          fillParameters: [createFillParameter()],
        };
      }

      onRun: {
        if (typeof curScore === 'undefined') {
          Qt.quit();
        }
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState == XMLHttpRequest.DONE) {
                var response = request.responseText
                console.log("responseText: " + response)
                Qt.quit()
            }
        }
        request.open("POST", "http://localhost:8000", true);
        request.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        request.send(JSON.stringify(createAutoFillRequest()));
        console.log("sent request");
      }
}
