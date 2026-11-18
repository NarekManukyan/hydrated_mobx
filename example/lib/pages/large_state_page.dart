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
  var _next = 0;
  var _busy = false;
  String? _result;

  Storage get _box => appStorages.documents;
  Storage get _files => appStorages.notes;

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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Writes notes through stores bound to the gzipped box.
  Future<String> _addToBox() async {
    for (var i = 0; i < _kNotesPerTap; i++) {
      final store = LargeNoteStore('${_next++}', _box)..write(_kLinesPerNote);
      await store.flush();
      store.dispose();
    }
    return 'Wrote $_kNotesPerTap notes to the "$kDocumentsBox" box, '
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
          '"$kDocumentsBox" box is built with encoding: gzipJson, so each '
          'note above 16 KB is kept as gzipped bytes and decoded only when a '
          'store hydrates. The "$kNotesDirectory" FileStorage keeps one file '
          'per note and holds nothing in memory until a note is read. '
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
