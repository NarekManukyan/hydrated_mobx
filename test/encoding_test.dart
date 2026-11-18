import 'dart:io';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _Notes extends HydratedMobX with Store {
  _Notes({super.storage});

  final Observable<List<String>> _lines = Observable(<String>[]);

  List<String> get lines => _lines.value;
  set lines(List<String> value) => runInAction(() => _lines.value = value);

  @override
  int get version => 2;

  @override
  String get storagePrefix => 'notes';

  @override
  Map<String, dynamic>? toJson() => {
        'lines': [..._lines.value],
      };

  @override
  void fromJson(Map<String, dynamic> json) =>
      _lines.value = (json['lines'] as List<dynamic>).cast<String>();
}

class _CountingStorage extends ForwardingStorage {
  _CountingStorage(super.inner);

  int writes = 0;

  @override
  Future<void> write(String key, dynamic value) {
    if (!HydratedMobX.isVersionKey(key)) writes++;
    return super.write(key, value);
  }
}

Map<String, dynamic> _big([String word = 'transcript']) => {
      'segments': [
        for (var i = 0; i < 500; i++)
          {'id': i, 'text': '$word $i', 'start': i * 1.5, 'final': i.isEven},
      ],
    };

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hydrated_encoding_');
  });

  tearDown(() => dir.delete(recursive: true));

  Future<HydratedStorage> build({
    HydratedEncoding encoding = HydratedEncoding.json,
    int encodeAbove = 1024,
  }) =>
      HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(dir.path),
        encoding: encoding,
        encodeAbove: encodeAbove,
      );

  /// What the box file holds for [key], read without hydrated_mobx.
  Future<Object?> raw(String key) async {
    final hive = Hive..init(dir.path);
    final box = await hive.openBox<dynamic>(HydratedStorage.defaultBoxName);
    final value = box.get(key);
    await box.close();
    return value;
  }

  for (final encoding in [HydratedEncoding.json, HydratedEncoding.gzipJson]) {
    test('$encoding keeps large state as bytes and reads it back', () async {
      var disk = await build(encoding: encoding);
      await disk.write('big', _big());
      expect(disk.read('big'), _big());
      await disk.close();

      expect(await raw('big'), isA<Uint8List>());
      disk = await build(encoding: encoding);
      expect(disk.read('big'), _big());
      await disk.close();
    });
  }

  test('gzipJson is smaller than json', () async {
    final json = await build();
    await json.write('big', _big());
    await json.close();
    final jsonSize = (await raw('big'))! as Uint8List;

    final gzip = await build(encoding: HydratedEncoding.gzipJson);
    await gzip.write('big', _big());
    await gzip.close();
    final gzipSize = (await raw('big'))! as Uint8List;

    expect(gzipSize.length, lessThan(jsonSize.length ~/ 3));
  });

  test('state below encodeAbove, and other values, stay as they are', () async {
    final bytes = Uint8List(4096)..[0] = 7;
    final disk = await build();
    await disk.write('small', {'count': 1});
    await disk.write('n', 3);
    await disk.write('bytes', bytes);
    await disk.close();

    expect(await raw('small'), {'count': 1});
    expect(await raw('n'), 3);
    expect(await raw('bytes'), bytes);
  });

  test('bytes that start like an encoded value stay as they are', () async {
    // The magic bytes with the format byte only a file storage writes, and
    // a PNG header, which shares the first magic byte.
    final header = Uint8List.fromList([0x89, 0x48, 0x4d, 0, 1, 2]);
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]);
    for (final encoding in [HydratedEncoding.json, HydratedEncoding.gzipJson]) {
      final disk = await build(encoding: encoding);
      await disk.write('header', header);
      await disk.write('png', png);
      await disk.close();

      expect(await raw('header'), header);
      expect(await raw('png'), png);
      final reopened = await build(encoding: encoding);
      expect(reopened.read('header'), header);
      expect(reopened.read('png'), png);
      await reopened.close();
    }
  });

  test('state JSON cannot hold stays a tree', () async {
    final disk = await build(encodeAbove: 0);
    await disk.write('intKeys', {1: 'a'});

    expect(disk.read('intKeys'), {1: 'a'});
    await disk.close();
    expect(await raw('intKeys'), {1: 'a'});
  });

  test('state stored as a tree is converted when the storage is built',
      () async {
    var disk = await build(encoding: HydratedEncoding.tree);
    await disk.write('big', _big());
    await disk.write('small', {'count': 1});
    await disk.close();
    expect(await raw('big'), isA<Map<dynamic, dynamic>>());

    disk = await build(encoding: HydratedEncoding.gzipJson);
    await disk.close();

    expect(await raw('big'), isA<Uint8List>());
    expect(await raw('small'), {'count': 1});
  });

  test('going back to tree decodes encoded state at build', () async {
    var disk = await build();
    await disk.write('big', _big());
    await disk.close();

    disk = await build(encoding: HydratedEncoding.tree);
    expect(disk.read('big'), _big());
    await disk.close();

    expect(await raw('big'), isA<Map<dynamic, dynamic>>());
  });

  test('a new encoding re-encodes state kept in the old one', () async {
    var disk = await build();
    await disk.write('big', _big());
    await disk.close();
    expect(((await raw('big'))! as Uint8List)[3], 1);

    disk = await build(encoding: HydratedEncoding.gzipJson);
    expect(disk.read('big'), _big());
    await disk.close();

    expect(((await raw('big'))! as Uint8List)[3], 2);
  });

  test('a raised encodeAbove turns state below it back into a tree', () async {
    var disk = await build();
    await disk.write('big', _big());
    await disk.close();

    disk = await build(encodeAbove: 1 << 20);
    await disk.close();

    expect(await raw('big'), isA<Map<dynamic, dynamic>>());
  });

  test('state is converted once per setting, not at every build', () async {
    var disk = await build();
    await disk.close();
    // A tree written behind the storage's back is left alone while the
    // setting stays the same, which shows no build walks the box again.
    final hive = Hive..init(dir.path);
    final box = await hive.openBox<dynamic>(HydratedStorage.defaultBoxName);
    await box.put('big', _big());
    await box.close();

    disk = await build();
    await disk.close();
    expect(await raw('big'), isA<Map<dynamic, dynamic>>());

    disk = await build(encoding: HydratedEncoding.gzipJson);
    expect(disk.keys, ['big']);
    await disk.close();
    expect(await raw('big'), isA<Uint8List>());
  });

  test('state written after clear() still goes back to tree', () async {
    var disk = await build();
    await disk.write('old', _big());
    await disk.clear();
    await disk.write('big', _big());
    await disk.close();

    disk = await build(encoding: HydratedEncoding.tree);
    await disk.close();

    expect(await raw('big'), isA<Map<dynamic, dynamic>>());
  });

  test('a value that does not decode does not stop the box opening', () async {
    var disk = await build();
    await disk.write('big', _big());
    await disk.close();
    // Encoded bytes whose body is not JSON.
    final hive = Hive..init(dir.path);
    final box = await hive.openBox<dynamic>(HydratedStorage.defaultBoxName);
    await box.put('bad', Uint8List.fromList([0x89, 0x48, 0x4d, 1, 0x7b]));
    await box.close();

    disk = await HydratedStorage.build(
      storageDirectory: HydratedStorageDirectory(dir.path),
      encoding: HydratedEncoding.gzipJson,
      trackUse: true,
      initialUseTime: (_, __) => null,
    );
    expect(disk.read('big'), _big());
    expect(() => disk.read('bad'), throwsFormatException);
    await disk.close();
  });

  test('encodeAbove is the largest size kept as a tree', () async {
    const state = {'k': 'v'}; // {"k":"v"}: 9 bytes
    var disk = await build(encodeAbove: 9);
    await disk.write('at', state);
    await disk.close();
    expect(await raw('at'), state);

    disk = await build(encodeAbove: 8);
    await disk.write('over', state);
    await disk.close();
    expect(await raw('over'), isA<Uint8List>());
  });

  test('a store hydrates from encoded state, with its version key', () async {
    var disk = await build(encodeAbove: 0);
    final store = _Notes(storage: disk)..lines = ['a', 'b'];
    await store.flush();
    store.dispose();
    await disk.close();
    expect(await raw('notes'), isA<Uint8List>());
    expect(await raw('notes.__version'), 2);

    disk = await build(encodeAbove: 0);
    final counting = _CountingStorage(disk);
    final again = _Notes(storage: counting);
    addTearDown(again.dispose);

    expect(again.lines, ['a', 'b']);
    // The decoded state compares equal to what was hydrated, so setting it
    // again writes nothing.
    again.lines = ['a', 'b'];
    await settle();
    expect(counting.writes, 0);
    again.lines = ['a', 'b', 'c'];
    await settle();
    expect(counting.writes, 1);
    await disk.close();
  });

  test('rejects a negative encodeAbove', () {
    expect(() => build(encodeAbove: -1), throwsArgumentError);
  });
}
