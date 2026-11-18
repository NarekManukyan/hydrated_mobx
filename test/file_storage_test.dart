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
        directory: dir.path,
        encoding: encoding,
        cacheBytes: cacheBytes,
        maxEntries: maxEntries,
        maxAge: maxAge,
        clock: () => now,
      );

  List<String> files() => [
        for (final entry in dir.listSync()) entry.uri.pathSegments.last,
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

  test('closed storage throws', () async {
    final disk = await build();
    await disk.close();

    expect(() => disk.read('a'), throwsA(isA<StorageClosedException>()));
    expect(disk.write('a', 1), throwsA(isA<StorageClosedException>()));
  });

  test('rejects values JSON cannot hold, and tree encoding', () async {
    final disk = await build();
    await expectLater(disk.write('a', {1: 2}), throwsA(anything));
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
