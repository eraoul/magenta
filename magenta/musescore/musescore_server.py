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
#
# USAGE:
#
# bazel-bin/magenta/musescore/musescore_server --bundle_file=/Users/epnichols/code/magenta/magenta/musescore/lookback_rnn.mag

r"""Webserver for interacting with MuseScore."""

import BaseHTTPServer
import json
import os

# internal imports
import tensorflow as tf
from google.protobuf import json_format
from google.protobuf import text_format
from magenta.protobuf import autofill_pb2
from magenta.protobuf import generator_pb2
from magenta.protobuf import music_pb2
from magenta.music import midi_io

import magenta.music as mm
import magenta

# from magenta.models.melody_rnn import melody_rnn_config_flags
from magenta.models.melody_rnn import melody_rnn_model
from magenta.models.melody_rnn import melody_rnn_sequence_generator




FLAGS = tf.app.flags.FLAGS
tf.app.flags.DEFINE_integer('port', 8000, 'Port the server should listen on')
tf.app.flags.DEFINE_string(
    'bundle_file', None,
    'Path to the bundle file.')
tf.app.flags.DEFINE_float(
    'temperature', 1.0,
    'The randomness of the generated melodies. 1.0 uses the unaltered softmax '
    'probabilities, greater than 1.0 makes melodies more random, less than 1.0 '
    'makes melodies less random.')
tf.app.flags.DEFINE_integer(
    'beam_size', 1,
    'The beam size to use for beam search when generating melodies.')
tf.app.flags.DEFINE_integer(
    'branch_factor', 1,
    'The branch factor to use for beam search when generating melodies.')
tf.app.flags.DEFINE_integer(
    'steps_per_iteration', 1,
    'The number of melody steps to take per beam search iteration.')


class MuseScoreHttpRequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
  def __init__(self, *args, **kwargs):

    # Load the specified bundle file into a generator_pb2.GeneratorBundle.
    bundle_file = os.path.expanduser(FLAGS.bundle_file)
    print 'Loading bundle file: ' + bundle_file
    bundle = magenta.music.read_bundle_file(bundle_file)

    # Get the config from the bundle.
    # TODO: Assumes melody_rnn_model.
    config_id = bundle.generator_details.id
    config = melody_rnn_model.default_configs[config_id]

    #config.hparams.parse(FLAGS.hparams)

    # Make the generator.
    self.generator_ = melody_rnn_sequence_generator.MelodyRnnSequenceGenerator(
        model=melody_rnn_model.MelodyRnnModel(config),
        details=config.details,
        steps_per_quarter=config.steps_per_quarter,
        bundle=bundle)

    BaseHTTPServer.BaseHTTPRequestHandler.__init__(self, *args, **kwargs)


  # auto_fill_request is an autofill_pb2.AutoFillRequest, which contains .noteSequence and .fillParameters
  def generate_notes(self, auto_fill_request):
    # Determine the primer sequence. This can be all the notes until the start of the fill range.
    # TODO:

    # TOOD: fill_parameters is a repeated field. We assume only 1 fill region.
    fill_parameters = auto_fill_request.fill_parameters[0]
    primer_sequence = mm.trim_note_sequence(auto_fill_request.note_sequence,
        fill_parameters.start_time, fill_parameters.end_time)
    start_time = fill_parameters.start_time
    end_time = fill_parameters.end_time


    if primer_sequence.tempos and primer_sequence.tempos[0].qpm:
      qpm = primer_sequence.tempos[0].qpm
    else:
      qpm = 120

    # Derive the total number of seconds to generate based on the QPM of the
    # priming sequence and the size of the fill region.
    seconds_per_step = 60.0 / qpm / self.generator_.steps_per_quarter
    #total_seconds = FLAGS.num_steps * seconds_per_step
    total_seconds = end_time - start_time

    # Specify start/stop time for generation based on starting generation at the
    # end of the priming sequence and continuing until the sequence is num_steps
    # long.
    generator_options = generator_pb2.GeneratorOptions()
    input_sequence = primer_sequence

    generate_section = generator_options.generate_sections.add(
        start_time=start_time,
        end_time=end_time)

    generator_options.args['temperature'].float_value = FLAGS.temperature
    generator_options.args['beam_size'].int_value = FLAGS.beam_size
    generator_options.args['branch_factor'].int_value = FLAGS.branch_factor
    generator_options.args[
      'steps_per_iteration'].int_value = FLAGS.steps_per_iteration
    tf.logging.debug('input_sequence: %s', input_sequence)
    tf.logging.debug('generator_options: %s', generator_options)

    # Finally, generate notes! Composing happens here.
    generated_sequence = self.generator_.generate(input_sequence, generator_options)

    # Debug: output to MIDI file.
    magenta.music.sequence_proto_to_midi_file(generated_sequence, '/tmp/musescore_magenta_out.midi')

    return generated_sequence


  def do_POST(self):
    print 'got post'
    post_json = self.rfile.read(int(self.headers['content-length']))
    print post_json
    auto_fill_request = json_format.Parse(post_json, autofill_pb2.AutoFillRequest())
    print text_format.MessageToString(auto_fill_request)

    # We have a fill request, which includes the fill range and the entire score note sequence.

    # For debugging: output the note sequence to MIDI.
    midi_io.sequence_proto_to_midi_file(
        auto_fill_request.note_sequence, '/tmp/musescore.midi')

    # Generate notes for the fill range.
    output_sequence = self.generate_notes(auto_fill_request)

    self.send_response(200)
    self.send_header("Content-Type", "application/json")
    self.end_headers()

    # score_fragment = {'notes':
    #                    [
    #                     {'pitch': 68, 'dur': 1},
    #                     {'pitch': 69, 'dur': 2},
    #                     {'pitch': 70, 'dur': 1.5}],
    #                   }

    # output_sequence = music_pb2.NoteSequence()
    # note = output_sequence.notes.add()
    # note.pitch = 68
    # note.start_time = 8
    # note.end_time = 8.5

    # note = output_sequence.notes.add()
    # note.pitch = 70
    # note.start_time = 8.5
    # note.end_time = 8.75

    # note = output_sequence.notes.add()
    # note.pitch = 69
    # note.start_time = 8.75
    # note.end_time = 9

    # print output_sequence
    print json_format.MessageToJson(output_sequence)
    self.wfile.write(json_format.MessageToJson(output_sequence))
    # self.wfile.write(json.dumps(output_sequence))


# bazel-bin/magenta/models/melody_rnn/melody_rnn_generate --config=lookback_rnn --bundle_file=/Users/epnichols/code/magenta/magenta/musescore/lookback_rnn.mag --output_dir=//Users/epnichols/code/magenta/magenta/musescore/generated --num_outputs=10  --num_steps=128 --primer_melody="[60, -2, -2, -2, 69, -2, -2, -2, 67, -2, -2, -2]"

def main(_):
  # Start Server.
  httpd = BaseHTTPServer.HTTPServer(
      ("", FLAGS.port), MuseScoreHttpRequestHandler)

  print "serving at port", FLAGS.port
  httpd.serve_forever()


if __name__ == '__main__':
  tf.app.run()
