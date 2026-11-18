// Measures the heap a HydratedStorage holds once its box is open, for each
// HydratedEncoding, with a box of note-sized states (a one-hour transcript
// each) that no store has hydrated.
//
// Run each encoding in its own process, so one run's garbage never counts
// towards another's:
//   for e in tree json gzipJson; do
//     ENCODING=$e dart run --enable-vm-service=0 \
//       --disable-service-auth-codes benchmark/memory_benchmark.dart
//   done
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math';

import 'package:hydrated_mobx/hydrated_mobx.dart';

const _notes = 200;
const _segmentsPerNote = 900;

const _words = [
  'we', 'should', 'ship', 'the', 'release', 'after', 'review', 'meeting', //
  'customer', 'feedback', 'roadmap', 'quarter', 'budget', 'design', 'mobile',
  'recording', 'transcript', 'speaker', 'action', 'item', 'follow', 'up',
];

Map<String, dynamic> _note(int n, Random random) => {
      'name': 'Meeting $n',
      'created_at': DateTime(2026, 11, 1 + n % 28).toIso8601String(),
      'duration': 3600,
      'transcript_segments': [
        for (var i = 0; i < _segmentsPerNote; i++)
          {
            'id': n * 100000 + i,
            'speaker_index': random.nextInt(4),
            'speech': {
              'text': [
                for (var w = 0; w < 10; w++)
                  _words[random.nextInt(_words.length)],
              ].join(' '),
              'start': i * 4.0,
              'end': i * 4.0 + 3.7,
              'language': 'en',
            },
          },
      ],
    };

/// A minimal VM service client: enough to force a GC and read the heap.
class _Vm {
  _Vm._(this._socket) {
    _socket.listen((message) {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      _pending.remove(json['id'])?.complete(json['result']);
    });
  }

  static Future<_Vm> connect() async {
    final uri = (await Service.getInfo()).serverWebSocketUri;
    if (uri == null) {
      throw StateError('Run with --enable-vm-service.');
    }
    return _Vm._(await WebSocket.connect(uri.toString()));
  }

  final WebSocket _socket;
  final _pending = <String, Completer<Object?>>{};
  var _id = 0;

  Future<Object?> _call(String method, Map<String, Object?> params) {
    final id = '${++_id}';
    final done = _pending[id] = Completer<Object?>();
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    _socket.add(jsonEncode(request));
    return done.future;
  }

  /// The heap in use after a full GC, in MB.
  Future<double> heapMb() async {
    // This program runs a single isolate.
    final vm = (await _call('getVM', {}))! as Map<String, dynamic>;
    final isolate = ((vm['isolates'] as List<dynamic>).single
        as Map<String, dynamic>)['id'];
    await _call('getAllocationProfile', {'isolateId': isolate, 'gc': true});
    final usage = await _call('getMemoryUsage', {'isolateId': isolate});
    return ((usage! as Map<String, dynamic>)['heapUsage'] as int) / 1048576;
  }

  Future<void> close() => _socket.close();
}

Future<void> main() async {
  final encoding = HydratedEncoding.values.byName(
    Platform.environment['ENCODING'] ?? HydratedEncoding.tree.name,
  );
  final dir = await Directory.systemTemp.createTemp('hydrated_memory_');
  final directory = HydratedStorageDirectory(dir.path);
  final vm = await _Vm.connect();

  var utf8Bytes = 0;
  final random = Random(7);
  final writer = await HydratedStorage.build(
    storageDirectory: directory,
    encoding: encoding,
  );
  for (var n = 0; n < _notes; n++) {
    final note = _note(n, random);
    utf8Bytes += utf8.encode(jsonEncode(note)).length;
    await writer.write('note_$n', note);
  }
  await writer.close();
  final fileMb =
      File('${dir.path}/${HydratedStorage.defaultBoxName}.hive').lengthSync() /
          1048576;

  final before = await vm.heapMb();
  final watch = Stopwatch()..start();
  final storage = await HydratedStorage.build(
    storageDirectory: directory,
    encoding: encoding,
  );
  final openMs = watch.elapsedMilliseconds;
  final heldMb = await vm.heapMb() - before;

  watch.reset();
  for (var n = 0; n < _notes; n++) {
    storage.read('note_$n');
  }
  final readMs = watch.elapsedMicroseconds / _notes / 1000;

  final jsonMb = utf8Bytes / 1048576;
  print(
    '${encoding.name.padRight(8)} '
    'heap +${heldMb.toStringAsFixed(1)} MB '
    '(${(heldMb / jsonMb).toStringAsFixed(2)}x the JSON) | '
    'file ${fileMb.toStringAsFixed(1)} MB | open $openMs ms | '
    'read ${readMs.toStringAsFixed(2)} ms/note | '
    '$_notes notes, ${jsonMb.toStringAsFixed(1)} MB of JSON',
  );

  await storage.close();
  await vm.close();
  await dir.delete(recursive: true);
}
