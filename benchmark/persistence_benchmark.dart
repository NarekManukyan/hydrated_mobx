// Measures what persistence costs: writes per change, writes on re-creation,
// time per write of a large state, and how eviction bounds the box.
//
// Run with: dart run benchmark/persistence_benchmark.dart
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

const _rapidChanges = 1000;
const _recreations = 100;
const _rows = 2000;
const _largeWrites = 50;
const _cachedItems = 500;

/// Counts the writes that reach the real storage.
class CountingStorage extends ForwardingStorage {
  CountingStorage(super.inner);

  int writes = 0;

  @override
  Future<void> write(String key, dynamic value) {
    writes++;
    return super.write(key, value);
  }
}

class Counter extends HydratedMobX with Store {
  Counter({super.storage, super.persistDelay, super.storeId});

  final Observable<int> _count = Observable(0);

  void increment() => runInAction(() => _count.value++);

  @override
  String get storagePrefix => 'counter';

  @override
  Map<String, dynamic>? toJson() => {'count': _count.value};

  @override
  void fromJson(Map<String, dynamic> json) =>
      _count.value = json['count'] as int? ?? 0;
}

class Feed extends HydratedMobX with Store {
  Feed({required this.trusted, super.storage});

  final bool trusted;
  final Observable<int> _revision = Observable(0);

  void touch() => runInAction(() => _revision.value++);

  @override
  String get storagePrefix => trusted ? 'feed_trusted' : 'feed';

  @override
  bool get trustToJson => trusted;

  @override
  Map<String, dynamic>? toJson() => {
        'revision': _revision.value,
        'rows': [
          for (var i = 0; i < _rows; i++)
            {
              'id': i,
              'title': 'Row $i',
              'tags': ['a', 'b'],
              'author': {'id': i % 50, 'name': 'Author ${i % 50}'},
            },
        ],
      };

  @override
  void fromJson(Map<String, dynamic> json) {}
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

Future<HydratedStorage> _open(Directory dir, {int? maxEntries}) =>
    HydratedStorage.build(
      storageDirectory: HydratedStorageDirectory(dir.path),
      maxEntries: maxEntries,
    );

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('hydrated_bench_');
  try {
    final disk = await _open(dir);

    // 1. Rapid changes, written at once vs coalesced.
    for (final delay in [Duration.zero, const Duration(milliseconds: 100)]) {
      final storage = CountingStorage(disk);
      final store = Counter(storage: storage, persistDelay: delay);
      await store.flush();
      storage.writes = 0;
      for (var i = 0; i < _rapidChanges; i++) {
        store.increment();
      }
      await store.flush();
      print('$_rapidChanges rapid changes, persistDelay '
          '${delay.inMilliseconds} ms: ${storage.writes} writes');
      await store.clearPersisted();
      store.dispose();
    }

    // 2. Re-creating a store over stored state.
    final storage = CountingStorage(disk);
    Counter(storage: storage)
      ..increment()
      ..dispose();
    await _settle();
    storage.writes = 0;
    for (var i = 0; i < _recreations; i++) {
      Counter(storage: storage).dispose();
    }
    await _settle();
    print('$_recreations re-creations of a hydrated store: '
        '${storage.writes} writes');

    // 3. Time per write of a large state.
    for (final trusted in [false, true]) {
      final feed = Feed(trusted: trusted, storage: disk);
      await feed.flush();
      final watch = Stopwatch()..start();
      final blocking = Stopwatch();
      for (var i = 0; i < _largeWrites; i++) {
        blocking.start();
        feed.touch(); // runs toJson, the traversal and the compare in place
        blocking.stop();
        await feed.flush();
      }
      watch.stop();
      final stored = disk.read(feed.storageToken) as Map;
      assert(stored['revision'] == _largeWrites, 'last write landed');
      final perWrite = watch.elapsedMicroseconds / _largeWrites / 1000;
      final perChange = blocking.elapsedMicroseconds / _largeWrites / 1000;
      print('$_rows-row state, trustToJson $trusted: '
          '${perChange.toStringAsFixed(2)} ms blocking per change, '
          '${perWrite.toStringAsFixed(1)} ms per write on disk');
      feed.dispose();
    }

    // 4. A per-id cache with and without maxEntries.
    await disk.clear();
    for (var i = 0; i < _cachedItems; i++) {
      Counter(storage: disk, storeId: '$i')
        ..increment()
        ..dispose();
    }
    await _settle();
    await disk.close();
    final file = File('${dir.path}/hydrated_box.hive');
    final before = file.lengthSync();
    final bounded = await _open(dir, maxEntries: 50);
    final kept = bounded.keys.length;
    await bounded.close();
    print('$_cachedItems cached ids: ${(before / 1024).toStringAsFixed(1)} KB; '
        'built with maxEntries 50: $kept keys kept');
  } finally {
    await dir.delete(recursive: true);
  }
}
