# Copyright 2016 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
r"""Webserver for interacting with MuseScore."""

import BaseHTTPServer
import json


# internal imports
import tensorflow as tf
from google.protobuf import json_format
from google.protobuf import text_format
from magenta.protobuf import autofill_pb2
from magenta.protobuf import generator_pb2
from magenta.protobuf import music_pb2
from magenta.music import midi_io


FLAGS = tf.app.flags.FLAGS
tf.app.flags.DEFINE_integer('port', 8000, 'Port the server should listen on')

class MuseScoreHttpRequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
  def do_POST(self):
    print 'got post'
    post_json = self.rfile.read(int(self.headers['content-length']))
    print post_json
    message = json_format.Parse(post_json, autofill_pb2.AutoFillRequest())
    print text_format.MessageToString(message)
    midi_io.sequence_proto_to_midi_file(
        message.note_sequence, '/tmp/musescore.midi')


    self.send_response(200)
    self.send_header("Content-Type", "application/json")
    self.end_headers()

    # score_fragment = {'notes':
    #                    [
    #                     {'pitch': 68, 'dur': 1},
    #                     {'pitch': 69, 'dur': 2},
    #                     {'pitch': 70, 'dur': 1.5}],
    #                   }

    output_sequence = music_pb2.NoteSequence()
    note = output_sequence.notes.add()
    note.pitch = 68
    note.start_time = 8
    note.end_time = 8.5

    note = output_sequence.notes.add()
    note.pitch = 70
    note.start_time = 8.5
    note.end_time = 8.75

    note = output_sequence.notes.add()
    note.pitch = 69
    note.start_time = 8.75
    note.end_time = 9

    # generated_sequence = generator.generate(input_sequence, generator_options)

    # print output_sequence
    print json_format.MessageToJson(output_sequence)
    self.wfile.write(json_format.MessageToJson(output_sequence))
    # self.wfile.write(json.dumps(output_sequence))

def main(_):
  httpd = BaseHTTPServer.HTTPServer(
      ("", FLAGS.port), MuseScoreHttpRequestHandler)

  print "serving at port", FLAGS.port
  httpd.serve_forever()


if __name__ == '__main__':
  tf.app.run()
