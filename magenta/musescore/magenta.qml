import QtQuick 2.0
import MuseScore 1.0

MuseScore {
      menuPath: "Plugins.Magenta"

      function createNoteSequence() {
        var noteSequence = {
          timeSignatures: [],
          keySignatures: [],
          tempos: [],
          notes: [],
          totalTime: curScore.duration,
          sourceType: 'SCORE',
          ticksPerBeat: 220,
        };

        var cursor = curScore.newCursor();
        var startStaff;
        var endStaff;
        var endTick;
        var fullScore = false;
        cursor.rewind(1);
        if (!cursor.segment) { // no selection
           fullScore = true;
           startStaff = 0; // start with 1st staff
           endStaff = curScore.nstaves - 1; // and end with last
           endTick = curScore.lastSegment.tick + 1;
        } else {
           startStaff = cursor.staffIdx;
           cursor.rewind(2);
           if (cursor.tick == 0) {
             // this happens when the selection includes
             // the last measure of the score.
             // rewind(2) goes behind the last segment (where
             // there's none) and sets tick=0
             endTick = curScore.lastSegment.tick + 1;
           } else {
             endTick = cursor.tick;
           }
           endStaff = cursor.staffIdx;
        }

        for (var staff = startStaff; staff <= endStaff; staff++) {
          for (var voice = 0; voice < 4; voice++) {
            if (fullScore) {
              cursor.rewind(0); // beginning of score
            } else {
              cursor.rewind(1); // beginning of selection
            }
            cursor.voice = voice;
            cursor.staffIdx = staff;


            for (; cursor.segment && cursor.tick < endTick; cursor.next()) {
              if (!cursor.element) {
                continue;
              }

              var elem = cursor.element;

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
                  nsNote.startTime = cursor.time / 1000;
                  nsNote.endTime = nsNote.startTime + durationSeconds;
                  nsNote.instrument = 0;
                  nsNote.program = 1;
                  nsNote.part = (staff * 4) + voice;
                  noteSequence.notes.push(nsNote);
                }
              }
            }
          }
        }

        return noteSequence;
      }

      onRun: {
        if (typeof curScore === 'undefined') {
          Qt.quit();
        }
        var noteSequence = createNoteSequence();
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
        request.send(JSON.stringify(noteSequence));
        console.log("sent request");
      }
}
