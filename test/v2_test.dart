import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Reads an observable on every write, as a counting or logging storage
/// might.
class _SpyStorage extends InMemoryStorage {
  _SpyStorage(this._seen);

  final Observable<int> _seen;
  int writes = 0;

  @override
  Future<void> write(String key, dynamic value) {
    writes += _seen.value >= 0 ? 1 : 0;
    return super.write(key, value);
  }
}

class _Counter extends HydratedMobX with Store {
  _Counter({
    super.storeId,
    super.storage,
    super.persistDelay,
    super.onStorageError,
    this.prefix = 'counter',
  });

  final String prefix;
  final Observable<int> _count = Observable(0);
  int fromJsonCalls = 0;
  int toJsonCalls = 0;

  int get count => _count.value;
  set count(int value) => runInAction(() => _count.value = value);

  void increment() => runInAction(() => _count.value++);

  @override
  String get storagePrefix => prefix;

  @override
  Map<String, dynamic>? toJson() {
    toJsonCalls++;
    return {'count': _count.value};
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    fromJsonCalls++;
    _count.value = json['count'] as int? ?? 0;
  }
}

/// Stores whatever map it holds; used for nested and trusted JSON.
class _Bag extends HydratedMobX with Store {
  _Bag({super.storage, this.trusted = false});

  final bool trusted;
  final Observable<Map<String, dynamic>> _data =
      Observable(<String, dynamic>{});
  Map<String, dynamic>? hydrated;

  Map<String, dynamic> get data => _data.value;
  set data(Map<String, dynamic> value) =>
      runInAction(() => _data.value = value);

  @override
  String get storagePrefix => 'bag';

  @override
  bool get trustToJson => trusted;

  @override
  Map<String, dynamic>? toJson() => {'data': _data.value};

  @override
  void fromJson(Map<String, dynamic> json) {
    hydrated = json;
    _data.value = json['data'] as Map<String, dynamic>? ?? {};
  }
}

/// Holds an object the traversal cannot encode.
class _Unencodable extends HydratedMobX with Store {
  _Unencodable({super.onStorageError});

  @override
  String get storagePrefix => 'unencodable';

  @override
  Map<String, dynamic>? toJson() => {'value': Object()};

  @override
  void fromJson(Map<String, dynamic> json) {}
}

/// Version 2 store whose migration drops version-1 data.
class _Dropping extends HydratedMobX with Store {
  _Dropping();

  final Observable<int> _count = Observable(0);
  bool fromJsonCalled = false;

  int get count => _count.value;

  @override
  String get storagePrefix => 'dropping';

  @override
  int get version => 2;

  @override
  Map<String, dynamic>? migrate(int oldVersion, Map<String, dynamic> old) =>
      null;

  @override
  Map<String, dynamic>? toJson() => {'count': _count.value};

  @override
  void fromJson(Map<String, dynamic> json) {
    fromJsonCalled = true;
    _count.value = json['count'] as int? ?? 0;
  }
}

class _Observer extends HydratedObserver {
  final storageErrors = <String>[];
  final hydrationErrors = <String>[];
  final migrations = <String>[];

  @override
  HydrationErrorBehavior onHydrationError(
    HydratedMobX store,
    Object error,
    StackTrace stackTrace,
  ) {
    hydrationErrors.add(store.storageToken);
    return HydrationErrorBehavior.retain;
  }

  @override
  void onStorageError(
    HydratedMobX store,
    Object error,
    StackTrace stackTrace,
  ) =>
      storageErrors.add(store.storageToken);

  @override
  void onMigrate(HydratedMobX store, int fromVersion, int toVersion) =>
      migrations.add('${store.storageToken}:$fromVersion->$toVersion');
}

void main() {
  late RecordingStorage storage;

  setUp(() {
    storage = RecordingStorage();
    HydratedMobX.storage = storage;
    HydratedMobX.observer = const HydratedObserver();
    HydratedMobX.defaultPersistDelay = Duration.zero;
  });

  group('persistDelay', () {
    const delay = Duration(milliseconds: 40);

    test('coalesces changes within the window into one write', () async {
      final store = _Counter(persistDelay: delay);
      addTearDown(store.dispose);
      await Future<void>.delayed(delay * 2);
      storage.writes.clear();

      for (var i = 0; i < 5; i++) {
        store.increment();
      }
      await settle();
      expect(storage.writes, isEmpty, reason: 'still inside the window');

      await Future<void>.delayed(delay * 2);
      expect(storage.writes, ['counter']);
      expect(storage.read('counter'), {'count': 5});
    });

    test('flush() writes the pending state at once', () async {
      final store = _Counter(persistDelay: const Duration(hours: 1))
        ..increment();
      addTearDown(store.dispose);

      await store.flush();

      expect(storage.read('counter'), {'count': 1});
    });

    test('flushAll() writes every pending store of a storage', () async {
      final a = _Counter(storeId: 'a', persistDelay: const Duration(hours: 1));
      final b = _Counter(storeId: 'b', persistDelay: const Duration(hours: 1));
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      a.increment();
      b.increment();

      await HydratedMobX.flushAll(storage: storage);

      expect(storage.read('countera'), {'count': 1});
      expect(storage.read('counterb'), {'count': 1});
    });

    test('dispose() starts the pending write instead of dropping it', () async {
      final store = _Counter(persistDelay: const Duration(hours: 1))
        ..increment()
        ..dispose();
      await settle();

      expect(storage.read('counter'), {'count': 1});
      store.increment();
      await settle();
      expect(storage.read('counter'), {'count': 1});
    });

    test('defaultPersistDelay applies to stores built without one', () async {
      HydratedMobX.defaultPersistDelay = const Duration(hours: 1);
      final store = _Counter()..increment();
      addTearDown(store.dispose);
      await settle();

      expect(storage.read('counter'), isNull);
      await store.flush();
      expect(storage.read('counter'), {'count': 1});
    });
  });

  group('unchanged state is not written', () {
    test('hydrating a stored state writes nothing back', () async {
      await storage.write('counter', {'count': 3});
      storage.writes.clear();

      final store = _Counter();
      addTearDown(store.dispose);
      await settle();

      expect(store.count, 3);
      expect(storage.writes, isEmpty);
    });

    test('a change back to the written value writes nothing', () async {
      final store = _Counter()..increment();
      addTearDown(store.dispose);
      await settle();
      storage.writes.clear();

      store
        ..count = 2
        ..count = 1;
      await settle();

      expect(storage.writes, ['counter', 'counter']);
      storage.writes.clear();
      store.count = 1;
      await settle();
      expect(storage.writes, isEmpty);
    });

    test('an emptied list is detected (no aliasing)', () async {
      final list = ObservableList<int>();
      final store = _Bag()..data = {'items': list};
      addTearDown(store.dispose);
      await settle();

      runInAction(() => store.data = {'items': list..add(1)});
      await settle();

      expect(storage.read('bag'), {
        'data': {
          'items': [1],
        },
      });
    });

    test('a failed write is retried by the next run', () async {
      final store = _Counter(
        persistDelay: const Duration(hours: 1),
        onStorageError: (_, __) {},
      );
      addTearDown(store.dispose);
      await store.flush();
      storage.failWrites = true;
      store.increment();
      await store.flush();

      storage
        ..failWrites = false
        ..writes.clear();
      // Back to the state whose write failed: it must be written again.
      store
        ..increment()
        ..count = 1;
      await store.flush();

      expect(storage.writes, ['counter']);
      expect(storage.read('counter'), {'count': 1});
    });
  });

  group('observer', () {
    test('receives storage errors of stores without a handler', () async {
      final observer = HydratedMobX.observer = _Observer();
      storage.failWrites = true;

      final store = _Counter();
      addTearDown(store.dispose);
      await settle();

      expect(observer.storageErrors, ['counter']);
    });

    test("a store's own handler wins over the observer", () async {
      final observer = HydratedMobX.observer = _Observer();
      storage.failWrites = true;
      final errors = <Object>[];

      final store = _Counter(onStorageError: (e, _) => errors.add(e));
      addTearDown(store.dispose);
      await settle();

      expect(errors, hasLength(1));
      expect(observer.storageErrors, isEmpty);
    });

    test('decides the behavior after a hydration error', () async {
      final observer = HydratedMobX.observer = _Observer();
      await storage.write('counter', 'not a map');

      final store = _Counter()..increment();
      addTearDown(store.dispose);
      await settle();

      expect(observer.hydrationErrors, ['counter']);
      expect(storage.read('counter'), 'not a map', reason: 'retained');
    });

    test('hears about migrations', () async {
      final observer = HydratedMobX.observer = _Observer();
      await storage.write('dropping', {'count': 1});

      final store = _Dropping();
      addTearDown(store.dispose);

      expect(observer.migrations, ['dropping:1->2']);
    });

    test('serialization failures reach the storage error handler', () async {
      final errors = <Object>[];
      final store = _Unencodable(onStorageError: (e, _) => errors.add(e));
      addTearDown(store.dispose);
      await settle();

      expect(errors.single, isA<HydratedUnsupportedError>());
    });
  });

  group('migrate returning null', () {
    test('drops old state without calling fromJson', () async {
      await storage.write('dropping', {'count': 9});

      final store = _Dropping();
      addTearDown(store.dispose);
      await settle();

      expect(store.fromJsonCalled, isFalse);
      expect(store.count, 0);
      expect(storage.read('dropping'), {'count': 0});
      expect(storage.read('dropping.__version'), 2);
    });
  });

  group('JSON on read', () {
    test('fromJson gets string-keyed maps and plain lists after a reopen',
        () async {
      final dir = await Directory.systemTemp.createTemp('hydrated_v2_');
      addTearDown(() => dir.delete(recursive: true));
      final directory = HydratedStorageDirectory(dir.path);

      var disk = await HydratedStorage.build(storageDirectory: directory);
      _Bag(storage: disk)
        ..data = {
          'rows': [
            {
              'id': 1,
              'tags': ['a'],
              'meta': {'deep': true},
            },
          ],
        }
        ..dispose();
      await settle();
      await disk.close();

      disk = await HydratedStorage.build(storageDirectory: directory);
      final store = _Bag(storage: disk);
      addTearDown(disk.close);
      addTearDown(store.dispose);

      final rows = store.data['rows'];
      expect(rows, isA<List<dynamic>>());
      final row = (rows as List).single;
      expect(row, isA<Map<String, dynamic>>());
      expect((row as Map)['meta'], isA<Map<String, dynamic>>());
      expect(row['tags'], ['a']);
    });

    test("fromJson's copy is not the storage's value", () async {
      final stored = {
        'data': {
          'list': [1],
        },
      };
      await storage.write('bag', stored);

      final store = _Bag();
      addTearDown(store.dispose);
      ((store.hydrated!['data'] as Map)['list'] as List).add(2);

      expect(stored, {
        'data': {
          'list': [1],
        },
      });
    });

    test('trustToJson writes the map as returned', () async {
      final store = _Bag(trusted: true)..data = {'a': 1};
      addTearDown(store.dispose);
      await settle();

      expect((storage.read('bag') as Map)['data'], same(store.data));
    });
  });

  group('storage binding', () {
    test('a store writes to the storage it was given', () async {
      final other = InMemoryStorage();
      final store = _Counter(storage: other)..increment();
      addTearDown(store.dispose);
      await settle();

      expect(other.read('counter'), {'count': 1});
      expect(storage.read('counter'), isNull);
    });

    test('hydrate() without storage keeps the bound one', () async {
      final other = InMemoryStorage({
        'counter': {'count': 4},
      });
      final store = _Counter(storage: other)..hydrate();
      addTearDown(store.dispose);

      expect(store.count, 4);
    });
  });

  group('clearAll', () {
    test('where: deletes matching keys only and suspends their stores',
        () async {
      final kept = _Counter(prefix: 'keep');
      final wiped = _Counter(prefix: 'wipe');
      addTearDown(kept.dispose);
      addTearDown(wiped.dispose);
      await storage.write('raw', 1);
      kept.increment();
      wiped.increment();
      await settle();

      await HydratedMobX.clearAll(where: (token) => token == 'wipe');
      kept.increment();
      wiped.increment();
      await settle();

      expect(storage.read('keep'), {'count': 2});
      expect(storage.read('wipe'), isNull);
      expect(storage.read('raw'), 1);
    });

    test('also deletes the version keys of matching tokens', () async {
      await storage.write('dropping', {'count': 1});
      await storage.write('dropping.__version', 2);

      await HydratedMobX.clearAll(where: (token) => token == 'dropping');

      expect(storage.keys, isEmpty);
    });

    test('resume: true writes the current state back', () async {
      final store = _Counter()..increment();
      addTearDown(store.dispose);
      await settle();

      await HydratedMobX.clearAll(resume: true);
      await settle();

      expect(storage.read('counter'), {'count': 1});
    });

    test("clearing one storage leaves another storage's stores persisting",
        () async {
      final other = InMemoryStorage();
      final here = _Counter();
      final there = _Counter(storage: other);
      addTearDown(here.dispose);
      addTearDown(there.dispose);

      await storage.clear();
      here.increment();
      there.increment();
      await settle();

      expect(storage.read('counter'), isNull);
      expect(other.read('counter'), {'count': 1});
    });

    test('deleteToken removes state and version and stops its store', () async {
      final store = _Counter(storeId: '1')..increment();
      addTearDown(store.dispose);
      await storage.write('counter1.__version', 1);
      await settle();

      await HydratedMobX.deleteToken('counter1');
      store.increment();
      await settle();

      expect(storage.keys, isEmpty);
    });
  });

  group('version keys', () {
    test('helpers map between tokens and version keys', () {
      expect(HydratedMobX.versionKeyOf('a'), 'a.__version');
      expect(HydratedMobX.isVersionKey('a.__version'), isTrue);
      expect(HydratedMobX.isVersionKey('a'), isFalse);
      expect(HydratedMobX.tokenOfKey('a.__version'), 'a');
      expect(HydratedMobX.tokenOfKey('a'), 'a');
    });
  });

  group('closed storage', () {
    test('InMemoryStorage throws StorageClosedException after close', () async {
      final closed = InMemoryStorage();
      await closed.close();

      expect(() => closed.read('k'), throwsA(isA<StorageClosedException>()));
      expect(
        () => closed.write('k', 1),
        throwsA(isA<StorageClosedException>()),
      );
    });

    test('a write to a closed HydratedStorage reaches onStorageError',
        () async {
      final dir = await Directory.systemTemp.createTemp('hydrated_v2_');
      addTearDown(() => dir.delete(recursive: true));
      final disk = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(dir.path),
      );
      final errors = <Object>[];
      final store = _Counter(
        storage: disk,
        onStorageError: (e, _) => errors.add(e),
      );
      addTearDown(store.dispose);
      await settle();
      await disk.close();

      store.increment();
      await settle();

      expect(errors.single, isA<StorageClosedException>());
    });
  });

  group('HydratedStorage', () {
    late Directory dir;
    late DateTime now;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hydrated_v2_');
      now = DateTime(2026);
    });

    tearDown(() => dir.delete(recursive: true));

    Future<HydratedStorage> build({
      String boxName = HydratedStorage.defaultBoxName,
      bool trackUse = true,
      Duration? maxAge,
      int? maxEntries,
      bool Function(String key)? evictable,
    }) =>
        HydratedStorage.build(
          storageDirectory: HydratedStorageDirectory(dir.path),
          boxName: boxName,
          trackUse: trackUse,
          maxAge: maxAge,
          maxEntries: maxEntries,
          evictable: evictable,
          clock: () => now,
        );

    test('boxes with different names are independent', () async {
      final session = await build(boxName: 'session');
      final account = await build(boxName: 'account');
      await session.write('k', 1);
      await account.write('k', 2);

      await session.clear();

      expect(session.read('k'), isNull);
      expect(account.read('k'), 2);
      await session.close();
      await account.close();
    });

    test('keys and deleteAll', () async {
      final disk = await build();
      await disk.write('a', 1);
      await disk.write('b', 2);
      await disk.write('c', 3);

      await disk.deleteAll(['a', 'c']);

      expect(disk.keys, ['b']);
      await disk.close();
    });

    test('maxAge evicts keys unused for that long, with version keys',
        () async {
      var disk = await build();
      await disk.write('old', 1);
      await disk.write('old.__version', 2);
      now = now.add(const Duration(days: 10));
      await disk.write('fresh', 1);
      await disk.close();

      now = now.add(const Duration(days: 1));
      disk = await build(maxAge: const Duration(days: 7));

      expect(disk.keys, ['fresh']);
      await disk.close();
    });

    test('hydrating keeps a key alive, a plain read does not', () async {
      var disk = await build();
      await disk.write('counter', {'count': 1});
      await disk.write('idle', 1);
      now = now.add(const Duration(days: 10));
      disk.read('idle');
      _Counter(storage: disk).dispose();
      await disk.close();

      disk = await build(maxAge: const Duration(days: 7));

      expect(disk.keys, ['counter']);
      await disk.close();
    });

    test('maxEntries keeps the most recently used keys', () async {
      var disk = await build();
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(hours: 1));
        await disk.write('k$i', i);
      }
      await disk.close();

      disk = await build(maxEntries: 2);

      expect(disk.keys.toSet(), {'k3', 'k4'});
      await disk.close();
    });

    test('evictable limits what eviction may touch', () async {
      var disk = await build();
      await disk.write('cache_a', 1);
      await disk.write('outbox', 1);
      await disk.close();

      now = now.add(const Duration(days: 30));
      disk = await build(
        maxAge: const Duration(days: 1),
        evictable: (key) => key.startsWith('cache_'),
      );

      expect(disk.keys, ['outbox']);
      await disk.close();
    });

    test('a storage that never evicts keeps no use times', () async {
      final disk = await build(trackUse: false);
      await disk.write('k', 1);
      await disk.close();

      expect(File('${dir.path}/hydrated_box__meta.hive').existsSync(), isFalse);
    });

    test('evict() stops the live stores of evicted keys', () async {
      final disk = await build();
      final store = _Counter(storage: disk)..increment();
      addTearDown(store.dispose);
      await settle();
      now = now.add(const Duration(days: 2));

      await disk.evict(olderThan: const Duration(days: 1));
      store.increment();
      await settle();

      expect(disk.keys, isEmpty);
      await disk.close();
    });

    test('keys written before eviction metadata are aged from now', () async {
      final hive = Hive..init(dir.path);
      final legacy = await hive.openBox<dynamic>('legacy');
      await legacy.put('k', 1);
      await legacy.close();

      final disk = await build(
        boxName: 'legacy',
        maxAge: const Duration(days: 1),
      );

      expect(disk.keys, ['k']);
      await disk.close();
    });
  });

  group('ForwardingStorage', () {
    test('clear() suspends the stores bound to the wrapper', () async {
      final wrapper = ForwardingStorage(InMemoryStorage());
      final store = _Counter(storage: wrapper);
      addTearDown(store.dispose);

      await wrapper.clear();
      store.increment();
      await settle();

      expect(wrapper.keys, isEmpty);
    });
  });

  group('review fixes', () {
    test('evict() on the inner storage stops stores bound to a wrapper',
        () async {
      final dir = await Directory.systemTemp.createTemp('hydrated_v2_');
      addTearDown(() => dir.delete(recursive: true));
      var now = DateTime(2026);
      final disk = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(dir.path),
        trackUse: true,
        clock: () => now,
      );
      addTearDown(disk.close);
      final store = _Counter(storage: ForwardingStorage(disk))..increment();
      addTearDown(store.dispose);
      await settle();
      now = now.add(const Duration(days: 2));

      await disk.evict(olderThan: const Duration(days: 1));
      store.increment();
      await settle();

      expect(disk.keys, isEmpty);
    });

    test('importData at version 1 drops a stale version key', () async {
      await storage.write('counter.__version', 3);

      await HydratedMobX.importData({
        'counter': {'count': 1},
      });

      expect(storage.read('counter.__version'), isNull);
    });

    test('a failed importData overwrite leaves no state under the new version',
        () async {
      await storage.write('counter', {'count': 1});
      storage.failKeys.add('counter');

      await expectLater(
        HydratedMobX.importData(
          {
            'counter': {'count': 9},
          },
          overwrite: true,
          version: 3,
        ),
        throwsException,
      );

      expect(storage.read('counter'), isNull);
    });

    test('a negative age is rejected', () async {
      final dir = await Directory.systemTemp.createTemp('hydrated_v2_');
      addTearDown(() => dir.delete(recursive: true));
      expect(
        () => HydratedStorage.build(
          storageDirectory: HydratedStorageDirectory(dir.path),
          maxAge: const Duration(days: -1),
        ),
        throwsArgumentError,
      );
      final disk = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(dir.path),
        trackUse: true,
      );
      addTearDown(disk.close);

      expect(
        () => disk.evict(olderThan: const Duration(days: -1)),
        throwsArgumentError,
      );
    });

    test('a throwing onMigrate keeps the migrated state', () async {
      HydratedMobX.observer = _ThrowingMigrateObserver();
      await storage.write('migrating', {'old': 4});
      final errors = <Object>[];

      final store = _Migrating(onStorageError: (e, _) => errors.add(e));
      addTearDown(store.dispose);

      expect(store.count, 4);
      expect(errors.single, isA<StateError>());
    });

    test('a write queued behind close() throws StorageClosedException',
        () async {
      final dir = await Directory.systemTemp.createTemp('hydrated_v2_');
      // Hive removes its lock file after close returns; don't race it.
      addTearDown(
        () => dir.delete(recursive: true).catchError(
              (Object _) => dir,
              test: (e) => e is FileSystemException,
            ),
      );
      final disk = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(dir.path),
      );

      // A write holds the lock, so close() and the next write queue behind
      // it; that write finds the box open now and closed on its turn.
      final first = disk.write('a', 1);
      final closing = disk.close();
      final queued = expectLater(
        disk.write('k', 1),
        throwsA(isA<StorageClosedException>()),
      );
      await first;
      await closing;
      await queued;
    });

    test('a token ending in the version suffix is rejected', () {
      expect(
        () => _Counter(prefix: 'x', storeId: '.__version'),
        throwsArgumentError,
      );
    });

    test('a negative maxEntries is rejected', () async {
      final dir = await Directory.systemTemp.createTemp('hydrated_v2_');
      addTearDown(() => dir.delete(recursive: true));
      final disk = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(dir.path),
        trackUse: true,
      );
      addTearDown(disk.close);

      expect(() => disk.evict(maxEntries: -1), throwsArgumentError);
    });

    test('a box name ending in the use-time suffix is rejected', () {
      expect(
        () => HydratedStorage.build(
          storageDirectory: const HydratedStorageDirectory('unused'),
          boxName: 'cache__meta',
        ),
        throwsArgumentError,
      );
    });

    test('evict() sees a use time markUsed queued just before it', () async {
      final dir = await Directory.systemTemp.createTemp('hydrated_v2_');
      addTearDown(() => dir.delete(recursive: true));
      var now = DateTime(2026);
      final disk = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(dir.path),
        trackUse: true,
        clock: () => now,
      );
      addTearDown(disk.close);
      await disk.write('k', 1);
      now = now.add(const Duration(days: 2));

      // A write holds the lock, so the use time queues behind it.
      final busy = disk.write('other', 2);
      disk.markUsed('k');
      await disk.evict(olderThan: const Duration(days: 1));
      await busy;

      expect(disk.read('k'), 1);
    });
  });

  group('untracked side effects', () {
    test('observables read by the storage do not re-run persistence', () async {
      final seen = Observable(0);
      final spy = _SpyStorage(seen);
      final store = _Counter(storage: spy);
      addTearDown(store.dispose);
      await settle();
      final runs = store.toJsonCalls;

      runInAction(() => seen.value++);
      await settle();

      expect(store.toJsonCalls, runs, reason: 'persistence did not re-run');
    });
  });

  group('rebindAll', () {
    test('moves live stores to the new storage', () async {
      final old = InMemoryStorage();
      final fresh = InMemoryStorage();
      final store = _Counter(storage: old);
      addTearDown(store.dispose);
      await settle();

      HydratedMobX.rebindAll(from: old, to: fresh);
      await old.close();
      store.increment();
      await settle();

      expect(fresh.read('counter'), {'count': 1});
    });
  });

  group('HydratedJson', () {
    test('readList accepts maps with dynamic keys, deeply', () {
      final json = <String, dynamic>{
        'items': [
          <dynamic, dynamic>{
            'a': <dynamic, dynamic>{'b': 1},
          },
          'skip me',
        ],
      };

      final items = HydratedJson.readList(json, 'items', (m) => m);

      expect(items.single['a'], isA<Map<String, dynamic>>());
    });

    test('readObject accepts maps with dynamic keys', () {
      final json = <String, dynamic>{
        'o': <dynamic, dynamic>{'x': 1},
      };

      expect(HydratedJson.readObject(json, 'o', (m) => m['x']), 1);
    });

    test('readStringList skips non-strings', () {
      final json = <String, dynamic>{
        'l': ['a', 1, 'b'],
      };

      expect(HydratedJson.readStringList(json, 'l'), ['a', 'b']);
    });
  });
}

class _ThrowingMigrateObserver extends HydratedObserver {
  @override
  void onMigrate(HydratedMobX store, int fromVersion, int toVersion) =>
      throw StateError('observer failed');
}

/// Version 2 store renaming `old` to `count`.
class _Migrating extends HydratedMobX with Store {
  _Migrating({super.onStorageError});

  final Observable<int> _count = Observable(0);

  int get count => _count.value;

  @override
  String get storagePrefix => 'migrating';

  @override
  int get version => 2;

  @override
  Map<String, dynamic>? migrate(int oldVersion, Map<String, dynamic> old) =>
      {'count': old['old']};

  @override
  Map<String, dynamic>? toJson() => {'count': _count.value};

  @override
  void fromJson(Map<String, dynamic> json) =>
      _count.value = json['count'] as int? ?? 0;
}
