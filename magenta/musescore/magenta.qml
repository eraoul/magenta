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

//import QtQuick 2.0
//import QtQuick 2.1
import QtQuick 2.2
import MuseScore 1.0
//import QtQuick.Controls 1.0
import QtQuick.Controls 1.2

import QtQuick.Layouts 1.0
import QtQuick.Controls.Private 1.0


MuseScore {
    menuPath:   "Plugins.magenta"
    version:  "2.1"
    description: "This plugin connects to a Magenta server to generate music for the selected region"

    pluginType: "dock"
    dockArea:   "left"

    width:  150
    height: 75
    onRun:  console.log("hello panel"); //  + pluginPath);

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
            console.error('Unknown key signature: ' + id);
            Qt.quit();
        }
      }

      function midiToNoteName(midi) {
        var noteNames = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
        var s = noteNames[midi % 12];
        s += (Math.floor(midi / 12) - 1);
        return s;
      }

      // Returns the part # for a given midiParts dictionary and track #.
      function getPartNumber(midiParts, track) {
        for (var i in midiParts) {
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
          tempos: [],
          notes: [],
          totalTime: curScore.duration,
          sourceInfo: {
            sourceType: 'SCORE_BASED',
            encoding_type: 'MUSESCORE',
            parser: 'MAGENTA_MUSESCORE',
          },
          ticks_per_quarter: 220,
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
        // Find all time signatures and tempo markings.
        // TODO: Directly insert these into noteSequence once we can calculate
        // the time from the tick: https://musescore.org/en/node/117611
        var timeSignatures = [];
        var prevTime = 0;
        var prevTick = 0;
        var prevTempo = 2;  // Default to 2 (=120bpm) at start of score.
        for(var seg = curScore.firstSegment(); !!seg; seg = seg.next) {
          for (var i = 0; i < seg.annotations.length; i++) {
            var annotation = seg.annotations[i];
            if (annotation.type === Element.TEMPO_TEXT) {
              var curBpm = 60 * annotation.tempo;
              var curTime = prevTime + (seg.tick - prevTick) / (480 * prevTempo);
              console.log("Tempo Change -- BPM: " + curBpm + " Tick: " + seg.tick + " Time: " + curTime);
              noteSequence.tempos.push(
                {
                  time: curTime,
                  qpm: curBpm,
                });
              prevTime = curTime;
              prevTick = seg.tick;
              prevTempo = annotation.tempo

            }
          }

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

              if (!cursor.element) {
                continue;
              }

              var elem = cursor.element;
              console.log("Element: " + elem.userName() + " at tick " + cursor.tick +
                          " time " + cursor.time);
              if (elem.type == Element.CHORD) {
                // TODO: gracenotes
                for (var i = 0; i < elem.notes.length; i++) {
                  var scoreNote = elem.notes[i];
                  console.log("Note: " + midiToNoteName(scoreNote.ppitch) + " dur: " +
                    (elem.globalDuration.ticks / 480));
                  // duration (seconds) = globalDuration.ticks /
                  //   (480 (musescore ticks per quarter note) *
                  //    tempo (quarter notes per second))
                  // globalDuration accounts for tuplets. duration does not.
                  var durationSeconds =
                      elem.globalDuration.ticks / (480 * cursor.tempo);

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
                  nsNote.voice = voice;
                  noteSequence.notes.push(nsNote);
                }
              }
            }
          }
        }

        return noteSequence;
      }

      // Set the given cursor duration based on a a number of seconds.
      // TODO: handle tempo changes during rest. Ignore for now; assume
      // tempo is constant from cursor start point until end of rest.
      function setCursorDurationSeconds(cursor, durationSec) {
        var tempoMultiplierVsSixty = cursor.tempo;
        // Quantize to 64th notes.  TODO: improve this, handle triplets.
        var sixtyFourthNotesPerSec = 16.0 * tempoMultiplierVsSixty;
        var numSixtyFourths = durationSec * sixtyFourthNotesPerSec;
        console.log("num64ths: " + numSixtyFourths);
        cursor.setDuration(numSixtyFourths, 64);
      }

      // Using the given cursor, add a rest of the specified duration.
      function addRestAtCursor(cursor, durationSec) {
        console.log("Creating rest of duration: " + durationSec)

        // The only way to add a rest currently in MuseScore is to add a note of the
        // desired duration and then to change it into a rest.

        // Save the cursor position.
        var position = cursor.tick;

        // Add a placeholder note.
        setCursorDurationSeconds(cursor, durationSec);
        cursor.addNote(0);

        // Rewind to the start of the selection and find where we were again.
        cursor.rewind(0);
        while (cursor.tick < position) {
          cursor.next();
        }

        var rest = newElement(Element.REST);
        rest.durationType = cursor.element.durationType;
        cursor.add(rest);
        cursor.next();
      }

      // Using the given cursor, add a note of the specified duration and pitch.
      // This is nontrivial if there are indicated tempo changes in the
      // region spanned by the rest. Also, the spelling of the pitch is
      // not well-specified with just the MIDI note number.
      // TODO: improve pitch spelling.
      function addNoteAtCursor(cursor, midiPitch, durationSec) {
        console.log("Creating note " + midiPitch + " of duration: " + durationSec);
        setCursorDurationSeconds(cursor, durationSec);
        cursor.addNote(midiPitch);
      }

      function fillSelectionWithGeneratedNotes(notes) {
        var cursor = curScore.newCursor();
        var track = 0;
        cursor.rewind(1);  // Go to start of selection.
        if (!cursor.segment) { // no selection
          console.error("No selection!");
        } else {
          track = cursor.track;
        }
        console.log("composing time");

        // TODO: Delete any existing notes in the selected region.
        // Otherwise this will overlay on top.

        curScore.startCmd();  // Set start of undoable score changes.
        cursor.track = track;
        cursor.voice = 0;  // TODO: Can we select/compose into a specific voice?
        for (var i = 0; i < notes.length; i++) {
          var note = notes[i];
          console.log(note['pitch']);
          var curTime = cursor.time / 1000.0
          console.log("time:" + curTime)
          // Add rests if necessary to move to cursor to start time of next note.
          if (Math.abs(curTime - note.startTime) > 0.01) {
            // Too much time until next note. Create a rest.
            addRestAtCursor(cursor, note.startTime - curTime);
          }

          // TODO: Compute note start time in ticks.

          // TOOD: If note is a tuplet, add required TUPLET elements to score.

          addNoteAtCursor(cursor, note['pitch'], note.endTime - note.startTime)
          //cursor.setDuration(1, 8);
          //cursor.addNote(note['pitch']);
        }
        curScore.endCmd();  // End undo region.
      }

      function createFillParameter() {
        var cursor = curScore.newCursor();
        cursor.rewind(1);  // Go to start of selection.
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
           cursor.rewind(2);  // Go to end of selection.
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

      function runMain() {
        if (typeof curScore === 'undefined') {
 //         Qt.quit();
             return;
        }
        var request = new XMLHttpRequest();
        request.onreadystatechange = function() {
            if (request.readyState == XMLHttpRequest.DONE) {
                var response = request.responseText;
                console.log("responseText: " + response);
                var jsonResponse = JSON.parse(response);
                fillSelectionWithGeneratedNotes(jsonResponse.notes);
                //Qt.quit()
                return;
            }
        }
        request.open("POST", "http://localhost:8000", true);
        request.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        request.send(JSON.stringify(createAutoFillRequest()));
        console.log("sent request");
      }

//    Rectangle {
//        color: "magenta"
//        anchors.fill: parent
//
//        Text {
//            horizontalAlignment: Text.AlignHCenter
//            verticalAlignment: Text.AlignVCenter
//            text: "Magenta"
//            }

//        MouseArea {
//            anchors.fill: parent
//            onClicked: runMain()
//            }
//        }

 GridLayout {
        anchors.fill: parent
        columns: 2
        rowSpacing: 5

        // Rectangle {
        //   color: "magenta"
        //   anchors.fill: parent

        //   Text {
        //     horizontalAlignment: Text.AlignHCenter
        //     verticalAlignment: Text.AlignVCenter
        //     text: "Magenta"
        //   }
        // }
          Image {
            Layout.columnSpan: 2
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Image.AlignHCenter
            source: "file:/Users/epnichols/code/magenta/magenta/musescore/magenta-logo.png"
              //source: "file:" + pluginPath + "/magenta-logo.png"
          }
      // Text {
      //   text: "MagentaWhite"
      //   color: "white"
      // }

      Button {
        text: "Generate"
        Layout.columnSpan: 2
        Layout.fillWidth: true
        onClicked: {
            runMain()
        }
      }
  }
}
