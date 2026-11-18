import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hydrated_mobx/file_storage.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _Note extends HydratedMobX with Store {
  _Note(String id, {super.storage}) : super(storeId: id);

  final Observable<String> _text = Observable('');

  String get text => _text.value;
  set text(String value) => runInAction(() => _text.value = value);

  @override
  int get version => 2;

  @override
  String get storagePrefix => 'note_';

  @override
  Map<String, dynamic>? toJson() => {'text': _text.value};

  @override
  void fromJson(Map<String, dynamic> json) =>
      _text.value = json['text'] as String;
}

/// Fails every attempt to set a use time.
class _NoUseTimes extends ForwardingStorage {
  _NoUseTimes(super.inner);

  @override
  Future<void> setUsedAt(String key, DateTime time) =>
      Future.error(const FileSystemException('read-only'));
}

/// Fails every write of one token's state.
class _FailingStorage extends ForwardingStorage {
  _FailingStorage(super.inner, {required this.failing});

  final String failing;

  @override
  Future<void> write(String key, dynamic value) async {
    if (key == failing) throw const FileSystemException('disk full');
    return super.write(key, value);
  }
}

Map<String, dynamic> _doc(int size) => {
      'lines': [for (var i = 0; i < size; i++) 'line $i of the document'],
    };

void main() {
  late Directory dir;
  late DateTime now;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hydrated_files_');
    now = DateTime(2026);
  });

  tearDown(() => dir.delete(recursive: true));

  Future<FileStorage> build({
    HydratedEncoding encoding = HydratedEncoding.gzipJson,
    int cacheBytes = FileStorage.defaultCacheBytes,
    int? maxEntries,
    Duration? maxAge,
  }) =>
      FileStorage.build(
        storageDirectory: HydratedStorageDirectory(dir.path),
        encoding: encoding,
        cacheBytes: cacheBytes,
        maxEntries: maxEntries,
        maxAge: maxAge,
        clock: () => now,
      );

  /// The files of keys and of writes in progress, not the lock file.
  List<String> files() => [
        for (final entry in dir.listSync())
          if (entry.uri.pathSegments.last != '.lock')
            entry.uri.pathSegments.last,
      ]..sort();

  for (final encoding in [HydratedEncoding.json, HydratedEncoding.gzipJson]) {
    test('$encoding values survive reopening', () async {
      var disk = await build(encoding: encoding);
      await disk.write('doc', _doc(100));
      await disk.write('doc.__version', 3);
      await disk.write('bytes', Uint8List.fromList([1, 2, 3]));
      await disk.close();

      disk = await build(encoding: encoding);
      expect(disk.keys.toSet(), {'doc', 'doc.__version', 'bytes'});
      expect(disk.read('doc'), _doc(100));
      expect(disk.read('doc.__version'), 3);
      expect(disk.read('bytes'), [1, 2, 3]);
      expect(disk.read('absent'), isNull);
      await disk.close();
    });
  }

  test('opening reads no values', () async {
    var disk = await build();
    for (var i = 0; i < 20; i++) {
      await disk.write('doc_$i', _doc(200));
    }
    await disk.close();

    disk = await build();
    expect(disk.cachedBytes, 0);
    disk.read('doc_3');
    expect(disk.cachedBytes, greaterThan(0));
    await disk.close();
  });

  test('the cache stays within cacheBytes, dropping the least recent',
      () async {
    final disk = await build(encoding: HydratedEncoding.json, cacheBytes: 5000);
    await disk.write('a', _doc(60));
    await disk.write('b', _doc(60));
    await disk.write('c', _doc(60));
    await disk.write('huge', _doc(2000));

    expect(disk.cachedBytes, lessThanOrEqualTo(5000));
    expect(disk.read('a'), _doc(60));
    expect(disk.read('huge'), _doc(2000));
    expect(disk.cachedBytes, lessThanOrEqualTo(5000));
    await disk.close();
  });

  test('the cache drops the least recently used value first', () async {
    final probe = await build(encoding: HydratedEncoding.json);
    await probe.write('x', _doc(60));
    final size = probe.cachedBytes;
    await probe.clear();
    await probe.close();

    // Room for two values: reading a makes b the least recent, so c's
    // write drops b and keeps a.
    final disk = await build(
      encoding: HydratedEncoding.json,
      cacheBytes: size * 2,
    );
    await disk.write('a', _doc(60));
    await disk.write('b', _doc(60));
    disk.read('a');
    await disk.write('c', _doc(60));
    expect(disk.cachedBytes, size * 2);

    // Removing the files shows which values the cache still holds.
    for (final name in files()) {
      File('${dir.path}/$name').deleteSync();
    }
    expect(disk.read('a'), _doc(60));
    expect(disk.read('c'), _doc(60));
    expect(disk.read('b'), isNull);
    await disk.close();
  });

  test('keys of any characters round-trip through file names', () async {
    const keys = ['a/b', 'folder:123', 'ünïcødé', '..', 'x.__version'];
    var disk = await build();
    for (final key in keys) {
      await disk.write(key, {'k': key});
    }
    await disk.close();

    disk = await build();
    expect(disk.keys.toSet(), keys.toSet());
    for (final key in keys) {
      expect(disk.read(key), {'k': key});
    }
    await disk.close();
  });

  test('keys differing only in case get files of their own', () async {
    // In base64 these pairs differ only in case, and so would share one
    // file where names ignore case.
    const keys = ['aaa', 'aaG', 'note_E', 'note__', 'A', 'a'];
    var disk = await build();
    for (final key in keys) {
      await disk.write(key, {'k': key});
    }
    await disk.close();

    final names = files();
    expect(names.map((name) => name.toLowerCase()).toSet(), hasLength(6));
    disk = await build();
    for (final key in keys) {
      expect(disk.read(key), {'k': key});
    }
    await disk.close();
  });

  test('a key fits only when its version key and temporary file do', () async {
    final disk = await build();
    final longest = 'k' * 144;
    await disk.write(longest, 1);
    await disk.write('$longest.__version', 2);
    expect(disk.read('$longest.__version'), 2);
    expect(() => disk.write('k' * 145, 1), throwsArgumentError);
    await disk.close();
  });

  test('one storage at a time per directory', () async {
    final disk = await build();
    await expectLater(build(), throwsStateError);
    await disk.close();

    final again = await build();
    await again.close();
  });

  test('another process cannot open the directory while it is open', () async {
    final disk = await build();
    final scripts = await Directory.systemTemp.createTemp('hydrated_lock_');
    addTearDown(() => scripts.delete(recursive: true));
    final script = File('${scripts.path}/lock.dart')..writeAsStringSync('''
import 'dart:io';

void main(List<String> args) {
  final file = File(args.single).openSync(mode: FileMode.write);
  try {
    file.lockSync();
    print('locked');
  } on FileSystemException {
    print('busy');
  }
}
''');
    final other = await Process.run(
      Platform.resolvedExecutable,
      [script.path, '${dir.path}/.lock'],
    );
    expect('${other.stdout}'.trim(), 'busy');
    await disk.close();
  });

  test('deleteAll removes state before its version key', () async {
    final disk = await build();
    await disk.write('doc.__version', 2);
    final version = files().single;
    await disk.write('doc', {'v': 1});
    final state = files().singleWhere((name) => name != version);
    // A directory in place of the version file makes deleting it fail.
    File('${dir.path}/$version').deleteSync();
    Directory('${dir.path}/$version').createSync();

    await expectLater(
      disk.deleteAll(['doc.__version', 'doc']),
      throwsA(isA<FileSystemException>()),
    );
    expect(File('${dir.path}/$state').existsSync(), isFalse);
    await disk.close();
  });

  test('a failed delete keeps the key listed, so a retry reaches it', () async {
    final disk = await build();
    await disk.write('doc.__version', 2);
    final version = files().single;
    await disk.write('doc', {'v': 1});
    File('${dir.path}/$version').deleteSync();
    Directory('${dir.path}/$version').createSync();

    await expectLater(
      disk.clear(),
      throwsA(isA<FileSystemException>()),
    );
    expect(disk.keys, ['doc.__version']);

    Directory('${dir.path}/$version').deleteSync();
    await disk.clear();
    expect(disk.keys, isEmpty);
    await disk.close();
  });

  test('build removes only its own unfinished writes', () async {
    var disk = await build();
    await disk.write('doc', {'v': 1});
    await disk.close();
    final own = '${files().single}.tmp';
    File('${dir.path}/$own').writeAsBytesSync([1]);
    File('${dir.path}/other.tmp').writeAsBytesSync([1]);

    disk = await build();
    expect(files(), isNot(contains(own)));
    expect(files(), contains('other.tmp'));
    await disk.close();
  });

  test('a write within the use resolution keeps the recorded use time',
      () async {
    final disk = await build();
    await disk.write('a', 1);
    final first = now;
    now = now.add(const Duration(seconds: 10));
    await disk.write('a', 2);
    expect(disk.usedAt('a'), first);
    now = now.add(const Duration(minutes: 1));
    await disk.write('a', 3);
    expect(disk.usedAt('a'), now);
    await disk.close();
  });

  test('a negative maxAge is reported under its own name', () async {
    await expectLater(
      build(maxAge: const Duration(days: -1)),
      throwsA(
        isA<ArgumentError>().having((e) => e.name, 'name', 'maxAge'),
      ),
    );
  });

  test('a write that never finished leaves the old value', () async {
    var disk = await build();
    await disk.write('doc', {'v': 1});
    await disk.close();
    final file = File('${dir.path}/${files().single}');
    File('${file.path}.tmp').writeAsBytesSync([0x89, 0x48]); // torn

    disk = await build();
    expect(disk.read('doc'), {'v': 1});
    expect(files(), hasLength(1));
    await disk.close();
  });

  test('a corrupt file fails hydration, not the storage', () async {
    var disk = await build();
    await disk.write('note_x', {'text': 'hi'});
    await disk.close();
    File('${dir.path}/${files().single}').writeAsStringSync('garbage');

    disk = await build();
    Object? error;
    final store = _Note(
      'x',
      storage: disk,
    )..hydrate(
        onHydrationError: (e, _) {
          error = e;
          return HydrationErrorBehavior.retain;
        },
      );
    addTearDown(store.dispose);

    expect(error, isA<FormatException>());
    expect(store.text, '');
    await disk.close();
  });

  test('a store hydrates, persists and preloads', () async {
    var disk = await build();
    final store = _Note('1', storage: disk)..text = 'hello';
    await store.flush();
    store.dispose();
    await disk.close();

    disk = await build();
    await disk.preload('note_1');
    expect(disk.cachedBytes, greaterThan(0));
    final again = _Note('1', storage: disk);
    addTearDown(again.dispose);
    expect(again.text, 'hello');
    await disk.close();
  });

  test('delete, deleteAll and clear remove the files', () async {
    final disk = await build();
    await disk.write('a', 1);
    await disk.write('b', 2);
    await disk.write('c', 3);

    await disk.delete('a');
    expect(disk.keys.toSet(), {'b', 'c'});
    await disk.deleteAll(['b', 'missing']);
    expect(files(), hasLength(1));
    await disk.clear();
    expect(disk.keys, isEmpty);
    expect(files(), isEmpty);
    await disk.close();
  });

  test('clear() suspends live stores', () async {
    final disk = await build();
    final store = _Note('1', storage: disk)..text = 'a';
    addTearDown(store.dispose);
    await store.flush();

    await disk.clear();
    store.text = 'b';
    await settle();

    expect(disk.keys, isEmpty);
    await disk.close();
  });

  test('evicts by use time, keeping live stores when asked', () async {
    var disk = await build();
    for (final (key, day) in [('old', 0), ('mid', 5), ('new', 9)]) {
      now = DateTime(2026, 1, day + 1);
      await disk.write(key, {'k': key});
      await disk.write('$key.__version', 2);
    }
    await disk.close();

    now = DateTime(2026, 1, 12);
    disk = await build(maxAge: const Duration(days: 8));
    expect(disk.keys.toSet(), {'mid', 'mid.__version', 'new', 'new.__version'});

    final live = _Note('live', storage: disk)..text = 'x';
    addTearDown(live.dispose);
    await live.flush();
    expect(await disk.evict(maxEntries: 0, keepLive: true), {'mid', 'new'});
    expect(disk.keys.toSet(), {'note_live', 'note_live.__version'});
    await disk.close();
  });

  test('usedAt reads and setUsedAt sets a use time, never a future one',
      () async {
    var disk = await build();
    await disk.write('a', 1);
    await disk.write('a.__version', 2);
    expect(disk.usedAt('a'), now);
    expect(disk.usedAt('a.__version'), isNull);
    expect(disk.usedAt('absent'), isNull);

    await disk.setUsedAt('a', DateTime(2025));
    await disk.setUsedAt('absent', DateTime(2025));
    expect(disk.usedAt('a'), DateTime(2025));
    await disk.close();

    disk = await build();
    expect(disk.usedAt('a'), DateTime(2025));
    await disk.setUsedAt('a', DateTime(2030));
    expect(disk.usedAt('a'), now);
    expect(disk.keys.toSet(), {'a', 'a.__version'});
    await disk.close();
  });

  test('usedAt is null when the use time cannot be read', () async {
    var disk = await build();
    await disk.write('a', 1);
    await disk.close();
    disk = await build();
    // Deleted behind the storage's back, so its time is not known.
    for (final name in files()) {
      File('${dir.path}/$name').deleteSync();
    }

    expect(disk.usedAt('a'), isNull);
    await disk.close();
  });

  test('markUsed keeps a key from looking stale', () async {
    var disk = await build();
    await disk.write('a', 1);
    now = now.add(const Duration(minutes: 5));
    await disk.write('b', 1);
    now = now.add(const Duration(minutes: 5));
    disk.markUsed('a');
    await settle();
    await disk.close();

    disk = await build(maxEntries: 1);
    expect(disk.keys, ['a']);
    await disk.close();
  });

  test('evict leaves out keys a queued delete hides', () async {
    final disk = await build();
    for (final key in ['a', 'b', 'c']) {
      await disk.write(key, 1);
      now = now.add(const Duration(minutes: 5));
    }
    // Holds the lock, so evict and the delete behind it both wait.
    final busy = disk.write('busy', 1);
    final evicting = disk.evict(
      maxEntries: 2,
      where: (key) => key != 'busy',
    );
    final deleting = disk.delete('c');

    await Future.wait([busy, deleting]);
    expect(await evicting, isEmpty);
    expect(disk.keys.toSet(), {'a', 'b', 'busy'});
    await disk.close();
  });

  test('evict leaves out a key whose delete is queued while it ranks',
      () async {
    var disk = await build();
    for (final key in ['a', 'b', 'c']) {
      await disk.write(key, 1);
      now = now.add(const Duration(minutes: 5));
    }
    await disk.close();
    // Reopened, so the use times are read from the files (in an isolate).
    disk = await build();
    Future<void>? deleting;

    final evicted = await disk.evict(
      maxEntries: 2,
      // Runs after the candidates are listed: c is still one of them.
      where: (key) {
        if (key == 'a') deleting = disk.delete('c');
        return true;
      },
    );
    await deleting;

    expect(evicted, isEmpty);
    expect(disk.keys.toSet(), {'a', 'b'});
    await disk.close();
  });

  test('a key written just before a clear stays hidden until it is wiped',
      () async {
    final disk = await build();
    for (final key in ['a', 'b', 'c']) {
      await disk.write(key, 1);
    }
    // Queued before the clear, so it lands first and the clear wipes it,
    // one file at a time.
    final writing = disk.write('new', 1);
    final clearing = disk.clear();
    final seen = <Object?>[];
    final done = writing.then((_) {
      seen
        ..add(disk.read('new'))
        ..add(disk.keys);
    });

    await Future.wait([done, clearing]);
    expect(seen, [isNull, isEmpty]);
    expect(disk.keys, isEmpty);
    await disk.close();
  });

  test('a write that fails leaves no temp file behind', () async {
    final disk = await build();
    await disk.write('a', 1);
    final name = files().single;
    await disk.delete('a');
    // A directory where the file goes makes the rename fail.
    Directory('${dir.path}/$name').createSync();

    await expectLater(disk.write('a', 2), throwsA(isA<FileSystemException>()));
    expect(
      dir
          .listSync()
          .map((entry) => entry.path)
          .where((p) => p.endsWith('.tmp')),
      isEmpty,
    );
    await disk.close();
  });

  test('a markUsed queued behind close leaves the file alone', () async {
    final disk = await build();
    await disk.write('a', 1);
    final file = File('${dir.path}/${files().single}');
    final written = file.lastModifiedSync();
    now = now.add(const Duration(days: 1));

    final busy = disk.write('b', 1);
    final closing = disk.close();
    disk.markUsed('a');
    await Future.wait([busy, closing]);
    await settle();

    expect(file.lastModifiedSync(), written);
  });

  test('a store built while a delete waits does not hydrate its value',
      () async {
    final disk = await build();
    await disk.write('note_1', {'text': 'old'});
    // Holds the lock, so the delete clearAll queues waits.
    final busy = disk.write('busy', 1);
    final deleting =
        HydratedMobX.clearAll(storage: disk, where: (t) => t == 'note_1');

    final note = _Note('1', storage: disk);
    expect(note.text, '');
    expect(disk.keys, isNot(contains('note_1')));

    await Future.wait([busy, deleting]);
    await note.flush();
    expect(disk.read('note_1'), {'text': ''});
    note.dispose();
    await disk.close();
  });

  test('closed storage throws', () async {
    final disk = await build();
    await disk.close();

    expect(() => disk.read('a'), throwsA(isA<StorageClosedException>()));
    expect(disk.write('a', 1), throwsA(isA<StorageClosedException>()));
  });

  test('rejects values JSON cannot hold, and tree encoding', () async {
    final disk = await build();
    await expectLater(
      disk.write('a', {1: 2}),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    expect(disk.keys, isEmpty);
    await disk.close();
    expect(
      () => build(encoding: HydratedEncoding.tree),
      throwsArgumentError,
    );
  });

  group('transferTokens', () {
    test('moves matching tokens with their version keys', () async {
      final box = InMemoryStorage({
        'note_1': {'text': 'a'},
        'note_1.__version': 2,
        'note_2': {'text': 'b'},
        'user': {'name': 'n'},
      });
      final disk = await build();

      final moved = await HydratedMobX.transferTokens(
        from: box,
        to: disk,
        where: (token) => token.startsWith('note_'),
      );

      expect(moved, {'note_1', 'note_2'});
      expect(box.keys, ['user']);
      expect(disk.keys.toSet(), {'note_1', 'note_1.__version', 'note_2'});
      expect(disk.read('note_1.__version'), 2);
      await disk.close();
    });

    test('keeps state the target holds differently, finishes the same',
        () async {
      final box = InMemoryStorage({
        'same': {'v': 1},
        'differs': {'v': 1},
      });
      final disk = await build();
      await disk.write('same', {'v': 1});
      await disk.write('differs', {'v': 2});

      final moved = await HydratedMobX.transferTokens(
        from: box,
        to: disk,
        where: (_) => true,
      );

      expect(moved, {'same'});
      expect(box.keys, ['differs']);
      expect(disk.read('differs'), {'v': 2});
      await disk.close();
    });

    test('refuses the same storage on both sides, wrapped or not', () async {
      final disk = await build();
      await disk.write('note_1', {'text': 'a'});

      for (final (from, to) in [
        (disk, disk),
        (disk, ForwardingStorage(disk)),
        (ForwardingStorage(ForwardingStorage(disk)), disk),
      ]) {
        await expectLater(
          HydratedMobX.transferTokens(from: from, to: to, where: (_) => true),
          throwsArgumentError,
        );
      }
      expect(disk.read('note_1'), {'text': 'a'});
      await disk.close();
    });

    test('moves state out of an encoded HydratedStorage, keeping use times',
        () async {
      final boxDir = await Directory.systemTemp.createTemp('hydrated_box_');
      addTearDown(() => boxDir.delete(recursive: true));
      final box = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(boxDir.path),
        encoding: HydratedEncoding.gzipJson,
        encodeAbove: 0,
        trackUse: true,
        clock: () => now,
      );
      // Used one day apart, in an order unlike the order of their keys.
      for (final (key, day) in [('note_c', 0), ('note_a', 1), ('note_b', 2)]) {
        now = DateTime(2026, 1, day + 1);
        await box.write(key, _doc(10));
      }
      now = DateTime(2026, 2);
      var disk = await build();

      final moved = await HydratedMobX.transferTokens(
        from: box,
        to: disk,
        where: (token) => token.startsWith('note_'),
      );
      await box.close();
      expect(moved, {'note_a', 'note_b', 'note_c'});
      expect(disk.read('note_a'), _doc(10));
      expect(disk.usedAt('note_b'), DateTime(2026, 1, 3));
      await disk.close();

      // The two used last survive, not the two first by key.
      disk = await build(maxEntries: 2);
      expect(disk.keys.toSet(), {'note_a', 'note_b'});
      await disk.close();
    });

    test('keeps use times through a ForwardingStorage', () async {
      final boxDir = await Directory.systemTemp.createTemp('hydrated_box_');
      addTearDown(() => boxDir.delete(recursive: true));
      final box = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(boxDir.path),
        trackUse: true,
        clock: () => now,
      );
      now = DateTime(2025);
      await box.write('note_1', {'text': 'a'});
      now = DateTime(2026, 2);
      final disk = await build();

      await HydratedMobX.transferTokens(
        from: ForwardingStorage(box),
        to: ForwardingStorage(disk),
        where: (_) => true,
      );

      expect(disk.usedAt('note_1'), DateTime(2025));
      // And back, through the wrapper's usedAt.
      expect(ForwardingStorage(disk).usedAt('note_1'), DateTime(2025));
      await box.close();
      await disk.close();
    });

    test('a use time that cannot be carried does not fail the move', () async {
      final boxDir = await Directory.systemTemp.createTemp('hydrated_box_');
      addTearDown(() => boxDir.delete(recursive: true));
      final box = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(boxDir.path),
        trackUse: true,
        clock: () => now,
      );
      await box.write('note_1', {'text': 'a'});
      final disk = await build();

      final moved = await HydratedMobX.transferTokens(
        from: box,
        to: _NoUseTimes(disk),
        where: (_) => true,
      );

      expect(moved, {'note_1'});
      expect(box.keys, isEmpty);
      expect(disk.read('note_1'), {'text': 'a'});
      await box.close();
      await disk.close();
    });

    test('a token that fails stays, the rest move, and the error is reported',
        () async {
      final box = InMemoryStorage({
        'note_1': {'text': 'a'},
        'note_2': {'text': 'b'},
        'note_2.__version': 2,
        'note_3': {'text': 'c'},
      });
      final disk = await build();
      final target = _FailingStorage(disk, failing: 'note_2');
      final errors = <String>[];

      final moved = await HydratedMobX.transferTokens(
        from: box,
        to: target,
        where: (_) => true,
        onError: (token, error, _) => errors.add(token),
      );

      expect(moved, {'note_1', 'note_3'});
      expect(errors, ['note_2']);
      expect(box.keys.toSet(), {'note_2', 'note_2.__version'});
      // The version written before the failed state write is taken back.
      expect(disk.keys.toSet(), {'note_1', 'note_3'});

      // Without onError the first failure is rethrown, after the others.
      box.write('note_4', {'text': 'd'}).ignore();
      await settle();
      await expectLater(
        HydratedMobX.transferTokens(from: box, to: target, where: (_) => true),
        throwsA(isA<FileSystemException>()),
      );
      expect(disk.keys, contains('note_4'));
      await disk.close();
    });

    test('a where that throws for one token fails only that token', () async {
      final box = InMemoryStorage({
        'note_1': {'text': 'a'},
        'note_2': {'text': 'b'},
      });
      final disk = await build();
      final errors = <String>[];

      final moved = await HydratedMobX.transferTokens(
        from: box,
        to: disk,
        where: (token) => token == 'note_2' ? throw StateError('bad') : true,
        onError: (token, error, _) => errors.add(token),
      );

      expect(moved, {'note_1'});
      expect(errors, ['note_2']);
      expect(box.keys, ['note_2']);
      await disk.close();
    });

    test('skips live stores bound to the storage a wrapper wraps', () async {
      final box = InMemoryStorage({
        'note_1': {'text': 'a'},
      });
      final store = _Note('1', storage: box);
      addTearDown(store.dispose);
      final disk = await build();

      final moved = await HydratedMobX.transferTokens(
        from: ForwardingStorage(box),
        to: disk,
        where: (_) => true,
      );

      expect(moved, isEmpty);
      expect(box.keys, contains('note_1'));
      expect(disk.keys, isEmpty);
      await disk.close();
    });

    test('a move finished after a crash keeps the use time', () async {
      final boxDir = await Directory.systemTemp.createTemp('hydrated_box_');
      addTearDown(() => boxDir.delete(recursive: true));
      final box = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(boxDir.path),
        trackUse: true,
        clock: () => now,
      );
      await box.write('note_1', {'text': 'a'});
      now = now.add(const Duration(days: 3));
      // The crashed run wrote the state, but not its use time.
      final disk = await build();
      await disk.write('note_1', {'text': 'a'});

      final moved = await HydratedMobX.transferTokens(
        from: box,
        to: disk,
        where: (_) => true,
      );

      expect(moved, {'note_1'});
      expect(disk.usedAt('note_1'), DateTime(2026));
      await box.close();
      await disk.close();
    });

    test('skips tokens of live stores', () async {
      final box = InMemoryStorage({
        'note_1': {'text': 'a'},
      });
      final store = _Note('1', storage: box);
      addTearDown(store.dispose);
      final disk = await build();

      final moved = await HydratedMobX.transferTokens(
        from: box,
        to: disk,
        where: (_) => true,
      );

      expect(moved, isEmpty);
      expect(disk.keys, isEmpty);
      await disk.close();
    });
  });
}
