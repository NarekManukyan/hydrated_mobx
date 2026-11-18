import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hydrated_mobx/file_storage.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import '../app/app_storages.dart';
import '../stores/large_note_store.dart';
import '../widgets/demo_page.dart';

const _kNotesPerTap = 10;
const _kLinesPerNote = 1000; // About 100 KB of JSON each.

class LargeStatePage extends StatefulWidget {
  const LargeStatePage({super.key});

  @override
  State<LargeStatePage> createState() => _LargeStatePageState();
}

class _LargeStatePageState extends State<LargeStatePage> {
  var _busy = false;
  String? _result;

  Storage get _box => appStorages.largeNotesBox;
  Storage get _files => appStorages.largeNotesFiles;

  List<String> _notes(Storage storage) => [
    for (final key in storage.keys)
      if (key.startsWith(kLargeNotePrefix) && !HydratedMobX.isVersionKey(key))
        key,
  ]..sort();

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The id after the highest one stored in either storage, so new notes
  /// never overwrite earlier ones.
  int _nextId() {
    var next = 0;
    for (final token in [..._notes(_box), ..._notes(_files)]) {
      final id = int.tryParse(token.substring(kLargeNotePrefix.length));
      if (id != null && id >= next) next = id + 1;
    }
    return next;
  }

  /// Writes notes through stores bound to the gzipped box.
  Future<String> _addToBox() async {
    final first = _nextId();
    for (var id = first; id < first + _kNotesPerTap; id++) {
      final store = LargeNoteStore('$id', _box)..write(_kLinesPerNote);
      try {
        await store.flush();
      } finally {
        // A live store's note would be skipped by the move to files.
        store.dispose();
      }
    }
    return 'Wrote $_kNotesPerTap notes to the "$kLargeNotesBox" box, '
        'each kept as gzipped JSON.';
  }

  /// Moves every note from the box into the file storage.
  Future<String> _moveToFiles() async {
    final moved = await HydratedMobX.transferTokens(
      from: _box,
      to: _files,
      where: (token) => token.startsWith(kLargeNotePrefix),
    );
    return 'Moved ${moved.length} notes to one file each.';
  }

  /// Opens the first note in the file storage: preloads it, then hydrates.
  Future<String> _openFromFiles() async {
    final notes = _notes(_files);
    if (notes.isEmpty) return 'No notes in files yet: move some first.';
    final token = notes.first;
    final watch = Stopwatch()..start();
    final files = _files;
    if (files is FileStorage) await files.preload(token);
    final preloaded = watch.elapsedMicroseconds;
    final store = LargeNoteStore(
      token.substring(kLargeNotePrefix.length),
      files,
    );
    final hydrated = watch.elapsedMicroseconds - preloaded;
    final lines = store.lines.length;
    store.dispose();
    return 'Opened $token: $lines lines. Preload took '
        '${(preloaded / 1000).toStringAsFixed(1)} ms off the UI path, '
        'hydrating ${(hydrated / 1000).toStringAsFixed(1)} ms.';
  }

  @override
  Widget build(BuildContext context) {
    final inBox = _notes(_box);
    final inFiles = _notes(_files);
    return DemoPage(
      title: 'Large state',
      explainer:
          'Hive keeps every value of an open box decoded in memory. The '
          '"$kLargeNotesBox" box is built with encoding: gzipJson, so each '
          'note above 16 KB is kept as gzipped bytes and decoded only when a '
          'store hydrates. The "$kLargeNotesDirectory" FileStorage keeps one '
          'file per note and holds nothing in memory until a note is read. '
          'transferTokens moves notes from the box to the files.',
      children: [
        Section(
          title: 'Notes',
          children: [
            Text('In the box: ${inBox.length} · in files: ${inFiles.length}'),
            if (_result case final result?) ...[
              const SizedBox(height: 8),
              Text(result, key: const Key('large_result')),
            ],
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('large_add'),
              onPressed: _busy ? null : () => unawaited(_run(_addToBox)),
              child: const Text('Add $_kNotesPerTap notes to the box'),
            ),
            OutlinedButton(
              key: const Key('large_move'),
              onPressed: _busy ? null : () => unawaited(_run(_moveToFiles)),
              child: const Text('Move them to files'),
            ),
            OutlinedButton(
              key: const Key('large_open'),
              onPressed: _busy ? null : () => unawaited(_run(_openFromFiles)),
              child: const Text('Open one from files'),
            ),
          ],
        ),
      ],
    );
  }
}
