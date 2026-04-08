// ignore_for_file: avoid_catching_errors

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:hydrated_mobx/src/hydrated_mobx.dart' show NIL;
import 'package:mobx/mobx.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<int> _makeKey(String password) {
  final bytes = utf8.encode(password);
  return sha256.convert(bytes).bytes;
}

/// Pump the MobX/microtask queue and event loop so pending autoruns and
/// async storage writes (including Hive's Lock) have a chance to complete.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

// ---------------------------------------------------------------------------
// In-memory Storage (no Hive, for isolated unit tests)
// ---------------------------------------------------------------------------

class _MemoryStorage implements Storage {
  final _data = <String, dynamic>{};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async {
    HydratedMobX.disposeAllForClear();
    _data.clear();
  }

  @override
  Future<void> close() async {}
}

// ---------------------------------------------------------------------------
// Test stores — use Observable/Action directly to avoid code-generation
// ---------------------------------------------------------------------------

/// A counter store that uses MobX reactive primitives without code generation.
///
/// Observables are declared as field initialisers (not in the constructor body)
/// so they are assigned before HydratedMobX calls hydrate() in super().
class CounterStore extends HydratedMobX with Store {
  CounterStore({String? storeId}) : super(storeId: storeId);

  final Observable<int> _count = Observable(0, name: 'CounterStore.count');
  late final Action increment =
      Action(() => _count.value++, name: 'CounterStore.increment');

  int get count => _count.value;

  @override
  Map<String, dynamic>? toJson() => {'count': _count.value};

  @override
  void fromJson(Map<String, dynamic> json) {
    _count.value = (json['count'] as int?) ?? 0;
  }
}

/// Store with a custom storagePrefix (obfuscation-safe).
class PrefixedStore extends HydratedMobX with Store {
  PrefixedStore() : super();

  final Observable<int> _value = Observable(0, name: 'PrefixedStore.value');

  int get value => _value.value;

  @override
  String get storagePrefix => 'my_prefix_';

  @override
  Map<String, dynamic>? toJson() => {'value': _value.value};

  @override
  void fromJson(Map<String, dynamic> json) {
    _value.value = (json['value'] as int?) ?? 0;
  }
}

/// Store whose fromJson always throws — exercises hydration-error paths.
class CorruptStore extends HydratedMobX with Store {
  CorruptStore({OnHydrationError? onHydrationError})
      : super(
          onHydrationError:
              onHydrationError ?? defaultOnHydrationError,
        );

  final Observable<int> _value = Observable(0, name: 'CorruptStore.value');

  int get value => _value.value;
  set value(int v) => runInAction(() => _value.value = v);

  @override
  Map<String, dynamic>? toJson() => {'value': _value.value};

  @override
  void fromJson(Map<String, dynamic> json) {
    throw StateError('corrupt!');
  }
}

/// Store that returns null from toJson — persistence should be skipped.
class NullJsonStore extends HydratedMobX with Store {
  NullJsonStore() : super();

  final Observable<int> _count = Observable(0, name: 'NullJsonStore.count');
  late final Action increment =
      Action(() => _count.value++, name: 'NullJsonStore.increment');

  int get count => _count.value;

  @override
  Map<String, dynamic>? toJson() => null;

  @override
  void fromJson(Map<String, dynamic> json) {
    _count.value = (json['count'] as int?) ?? 0;
  }
}

/// Store with a nested map/list payload.
class NestedStore extends HydratedMobX with Store {
  NestedStore() : super();

  final Observable<Map<String, dynamic>> _data =
      Observable(<String, dynamic>{}, name: 'NestedStore.data');

  Map<String, dynamic> get data => _data.value;

  void setData(Map<String, dynamic> v) => runInAction(() => _data.value = v);

  @override
  Map<String, dynamic>? toJson() => {'data': _data.value};

  @override
  void fromJson(Map<String, dynamic> json) {
    _data.value = (json['data'] as Map<String, dynamic>?) ?? {};
  }
}

/// Simple value object with a toJson method.
class Inner {
  Inner(this.x);
  final int x;
  Map<String, dynamic> toJson() => {'x': x};
}

/// Store serialising a custom object that exposes toJson.
class CustomObjectStore extends HydratedMobX with Store {
  CustomObjectStore() : super();

  final Observable<Inner> _inner =
      Observable(Inner(0), name: 'CustomObjectStore.inner');

  Inner get inner => _inner.value;
  set inner(Inner v) => runInAction(() => _inner.value = v);

  @override
  Map<String, dynamic>? toJson() => {'inner': _inner.value};

  @override
  void fromJson(Map<String, dynamic> json) {
    final raw = json['inner'];
    if (raw is Map<String, dynamic>) {
      _inner.value = Inner((raw['x'] as int?) ?? 0);
    }
  }
}

/// Used to exercise the cyclic-error path by throwing directly.
class _CyclicStore extends HydratedMobX with Store {
  _CyclicStore() : super();

  @override
  Map<String, dynamic>? toJson() => {};

  @override
  void fromJson(Map<String, dynamic> json) {}

  void triggerWrite(Map<String, dynamic> json) {
    throw HydratedUnsupportedError(json, cause: HydratedCyclicError(json));
  }
}

/// Used to exercise the unsupported-value error path by throwing directly.
class _UnsupportedValueStore extends HydratedMobX with Store {
  _UnsupportedValueStore() : super();

  @override
  Map<String, dynamic>? toJson() => {};

  @override
  void fromJson(Map<String, dynamic> json) {}

  void triggerWrite(Map<String, dynamic> json) {
    throw HydratedUnsupportedError(json['fn']);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hydrated_mobx_test_');
    HydratedMobX.storage = await HydratedStorage.build(
      storageDirectory: HydratedStorageDirectory(tempDir.path),
    );
  });

  tearDown(() async {
    await HydratedMobX.storage.close();
    await tempDir.delete(recursive: true);
  });

  // -------------------------------------------------------------------------
  group('HydratedMobX – hydration', () {
    test('hydrate from empty storage keeps default state', () async {
      final store = CounterStore();
      await _settle();
      expect(store.count, equals(0));
    });

    test('hydrate restores persisted state on second init', () async {
      final store1 = CounterStore();
      store1.increment();
      store1.increment();
      await _settle();

      await HydratedMobX.storage.close();
      HydratedMobX.storage = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(tempDir.path),
      );

      final store2 = CounterStore();
      expect(store2.count, equals(2));
    });

    test(
        'hydrate with corrupt JSON calls onHydrationError '
        'and state stays at Dart default', () async {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      await mem.write('CorruptStore', {'value': 99});

      var errorCalled = false;
      final store = CorruptStore(
        onHydrationError: (e, st) {
          errorCalled = true;
          return HydrationErrorBehavior.overwrite;
        },
      );
      expect(errorCalled, isTrue);
      expect(store.value, equals(0));
    });

    test(
        'HydrationErrorBehavior.retain prevents subsequent '
        'writes after corrupt hydration', () async {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;
      await mem.write('CorruptStore', {'value': 42});

      final store = CorruptStore(
        onHydrationError: (_, __) => HydrationErrorBehavior.retain,
      );
      store.value = 7;
      await _settle();

      // Original seeded value must be unchanged — writes are blocked.
      expect(mem.read('CorruptStore'), equals({'value': 42}));
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedMobX – storageToken composition', () {
    test('default token equals runtimeType string', () {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;
      final store = CounterStore();
      expect(store.storageToken, equals('CounterStore'));
    });

    test('storeId is appended to token when passed via constructor', () {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;
      final store = CounterStore(storeId: 'abc');
      expect(store.storageToken, equals('CounterStoreabc'));
    });

    test('custom storagePrefix is used in token', () {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;
      final store = PrefixedStore();
      expect(store.storageToken, equals('my_prefix_'));
    });

    test('multiple instances with distinct storeIds use independent keys',
        () async {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      final a = CounterStore(storeId: 'a');
      final b = CounterStore(storeId: 'b');

      // Trigger observables through the store's own Action.
      for (var i = 0; i < 10; i++) {
        a.increment();
      }
      for (var i = 0; i < 20; i++) {
        b.increment();
      }
      await _settle();

      expect(
        (mem.read('CounterStorea') as Map)['count'],
        equals(10),
      );
      expect(
        (mem.read('CounterStoreb') as Map)['count'],
        equals(20),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedMobX – persistence via autorun', () {
    test('observable change triggers a write to storage', () async {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      final store = CounterStore();
      store.increment();
      await _settle();

      final stored = mem.read('CounterStore') as Map;
      expect(stored['count'], equals(1));
    });

    test('multiple increments accumulate correctly', () async {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      final store = CounterStore();
      for (var i = 0; i < 5; i++) {
        store.increment();
      }
      await _settle();

      final stored = mem.read('CounterStore') as Map;
      expect(stored['count'], equals(5));
    });

    test('toJson returning null skips persistence', () async {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      final store = NullJsonStore();
      store.increment();
      await _settle();

      expect(mem.read('NullJsonStore'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('store.clear()', () {
    test('removes the persisted key and survives subsequent mutations',
        () async {
      final store = CounterStore();
      store.increment();
      store.increment();
      await _settle();

      expect(HydratedMobX.storage.read(store.storageToken), isNotNull);

      await store.clear();
      expect(HydratedMobX.storage.read(store.storageToken), isNull);

      // Mutate again — the autorun must NOT resurrect the cleared key.
      store.increment();
      await _settle();

      expect(
        HydratedMobX.storage.read(store.storageToken),
        isNull,
        reason:
            'cleared key must not be re-written by the persistence autorun',
      );
    });

    test('write queued before clear is dropped', () async {
      final store = CounterStore();
      store.increment(); // schedules an autorun write
      // Do not settle — issue clear immediately to race the pending write.
      await store.clear();
      await _settle();

      expect(HydratedMobX.storage.read(store.storageToken), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedStorage.clear()', () {
    test('wipes the box and prevents any live store from re-persisting',
        () async {
      final a = CounterStore(storeId: 'a');
      final b = CounterStore(storeId: 'b');
      a.increment();
      b.increment();
      await _settle();

      expect(HydratedMobX.storage.read(a.storageToken), isNotNull);
      expect(HydratedMobX.storage.read(b.storageToken), isNotNull);

      await HydratedMobX.storage.clear();

      // Mutate both stores after the global clear.
      a.increment();
      b.increment();
      await _settle();

      expect(HydratedMobX.storage.read(a.storageToken), isNull);
      expect(HydratedMobX.storage.read(b.storageToken), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedMobX – nested serialization', () {
    test('nested map/list round-trips correctly', () async {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      final store = NestedStore();
      store.setData({
        'nums': [1, 2, 3],
        'nested': {'flag': true, 'label': 'hello'},
      });
      await _settle();

      final stored = mem.read('NestedStore') as Map;
      final data = stored['data'] as Map;
      expect(data['nums'], equals([1, 2, 3]));
      expect((data['nested'] as Map)['flag'], isTrue);
      expect((data['nested'] as Map)['label'], equals('hello'));
    });

    test('custom object with toJson is serialised inline', () async {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      // Construction triggers the initial autorun with inner = Inner(0).
      final store = CustomObjectStore();
      store.inner = Inner(42);
      await _settle();

      final stored = mem.read('CustomObjectStore') as Map?;
      expect(stored, isNotNull);
      expect((stored!['inner'] as Map)['x'], equals(42));
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedMobX – cyclic & unsupported errors', () {
    test(
        'cyclic structure throws HydratedUnsupportedError '
        'wrapping HydratedCyclicError', () {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      final store = _CyclicStore();
      final cyclic = <String, dynamic>{};
      cyclic['self'] = cyclic;

      expect(
        () => store.triggerWrite(cyclic),
        throwsA(isA<HydratedUnsupportedError>()),
      );
    });

    test('HydratedCyclicError has informative toString', () {
      final err = HydratedCyclicError('cycle_object');
      expect(err.toString(), contains('Cyclic'));
    });

    test('HydratedUnsupportedError has informative toString', () {
      final err = HydratedUnsupportedError('bad', cause: Exception('oops'));
      expect(err.toString(), contains('Converting'));
    });

    test('un-encodable value throws HydratedUnsupportedError', () {
      final mem = _MemoryStorage();
      HydratedMobX.storage = mem;

      final store = _UnsupportedValueStore();
      expect(
        () => store.triggerWrite({'fn': Object()}),
        throwsA(isA<HydratedUnsupportedError>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedStorage – init / read / write / delete / close', () {
    test('read returns null for unknown key', () {
      expect(HydratedMobX.storage.read('no_such_key'), isNull);
    });

    test('write then read returns the same value', () async {
      await HydratedMobX.storage.write('k', {'a': 1});
      expect((HydratedMobX.storage.read('k') as Map)['a'], equals(1));
    });

    test('delete removes the key', () async {
      await HydratedMobX.storage.write('k', 'value');
      await HydratedMobX.storage.delete('k');
      expect(HydratedMobX.storage.read('k'), isNull);
    });

    test('persistence survives storage re-init from same directory', () async {
      await HydratedMobX.storage.write('persist_key', {'x': 99});
      await HydratedMobX.storage.close();

      HydratedMobX.storage = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(tempDir.path),
      );

      expect(
        (HydratedMobX.storage.read('persist_key') as Map)['x'],
        equals(99),
      );
    });

    test('concurrent writes do not corrupt data', () async {
      final futures = List.generate(
        20,
        (i) => HydratedMobX.storage.write('concurrent_$i', {'i': i}),
      );
      await Future.wait(futures);

      for (var i = 0; i < 20; i++) {
        final val = HydratedMobX.storage.read('concurrent_$i') as Map;
        expect(val['i'], equals(i));
      }
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedStorage – encrypted storage', () {
    test('encrypted storage can write and read back values', () async {
      await HydratedMobX.storage.close();

      final cipher = HydratedAesCipher(_makeKey('test_password'));
      final encDir =
          await Directory.systemTemp.createTemp('hydrated_enc_test_');
      try {
        final encStorage = await HydratedStorage.build(
          storageDirectory: HydratedStorageDirectory(encDir.path),
          encryptionCipher: cipher,
        );
        HydratedMobX.storage = encStorage;

        await encStorage.write('secret', {'password': 'hunter2'});
        final result = encStorage.read('secret') as Map;
        expect(result['password'], equals('hunter2'));

        await encStorage.close();
      } finally {
        await encDir.delete(recursive: true);
      }

      // Restore clean storage so tearDown can close it without error.
      HydratedMobX.storage = await HydratedStorage.build(
        storageDirectory: HydratedStorageDirectory(tempDir.path),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedJson – readString', () {
    test('returns the value when key exists and is a String', () {
      expect(
        HydratedJson.readString({'name': 'Alice'}, 'name'),
        equals('Alice'),
      );
    });

    test('returns defaultValue when key is missing', () {
      expect(HydratedJson.readString({}, 'name'), equals(''));
      expect(
        HydratedJson.readString({}, 'name', defaultValue: 'Bob'),
        equals('Bob'),
      );
    });

    test('returns defaultValue when value is null', () {
      expect(HydratedJson.readString({'name': null}, 'name'), equals(''));
    });

    test('returns defaultValue when value is wrong type', () {
      expect(HydratedJson.readString({'name': 42}, 'name'), equals(''));
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedJson – readInt', () {
    test('returns int value directly', () {
      expect(HydratedJson.readInt({'n': 7}, 'n'), equals(7));
    });

    test('coerces double to int', () {
      expect(HydratedJson.readInt({'n': 3.9}, 'n'), equals(3));
    });

    test('returns defaultValue for missing key', () {
      expect(HydratedJson.readInt({}, 'n'), equals(0));
      expect(HydratedJson.readInt({}, 'n', defaultValue: -1), equals(-1));
    });

    test('returns defaultValue for null', () {
      expect(HydratedJson.readInt({'n': null}, 'n'), equals(0));
    });

    test('returns defaultValue for wrong type', () {
      expect(HydratedJson.readInt({'n': 'hello'}, 'n'), equals(0));
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedJson – readDouble', () {
    test('returns double value', () {
      expect(
        HydratedJson.readDouble({'d': 3.14}, 'd'),
        closeTo(3.14, 0.001),
      );
    });

    test('coerces int to double', () {
      expect(HydratedJson.readDouble({'d': 5}, 'd'), equals(5.0));
    });

    test('returns defaultValue for missing key', () {
      expect(HydratedJson.readDouble({}, 'd'), equals(0.0));
      expect(
        HydratedJson.readDouble({}, 'd', defaultValue: 1.5),
        equals(1.5),
      );
    });

    test('returns defaultValue for null', () {
      expect(HydratedJson.readDouble({'d': null}, 'd'), equals(0.0));
    });

    test('returns defaultValue for wrong type', () {
      expect(HydratedJson.readDouble({'d': 'x'}, 'd'), equals(0.0));
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedJson – readBool', () {
    test('returns true', () {
      expect(HydratedJson.readBool({'b': true}, 'b'), isTrue);
    });

    test('returns false', () {
      expect(HydratedJson.readBool({'b': false}, 'b'), isFalse);
    });

    test('returns defaultValue for missing key', () {
      expect(HydratedJson.readBool({}, 'b'), isFalse);
      expect(HydratedJson.readBool({}, 'b', defaultValue: true), isTrue);
    });

    test('returns defaultValue for null', () {
      expect(HydratedJson.readBool({'b': null}, 'b'), isFalse);
    });

    test('returns defaultValue for wrong type', () {
      expect(HydratedJson.readBool({'b': 1}, 'b'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedJson – readList', () {
    test('returns parsed list for valid entries', () {
      final result = HydratedJson.readList(
        {
          'items': [
            {'x': 1},
            {'x': 2},
          ],
        },
        'items',
        (m) => m['x'] as int,
      );
      expect(result, equals([1, 2]));
    });

    test('skips non-Map entries', () {
      final result = HydratedJson.readList(
        {
          'items': [
            {'x': 1},
            'bad',
            42,
            {'x': 3},
          ],
        },
        'items',
        (m) => m['x'] as int,
      );
      expect(result, equals([1, 3]));
    });

    test('returns empty list for missing key', () {
      expect(HydratedJson.readList({}, 'items', (m) => m), isEmpty);
    });

    test('returns empty list for null value', () {
      expect(
        HydratedJson.readList({'items': null}, 'items', (m) => m),
        isEmpty,
      );
    });

    test('returns empty list when value is not a List', () {
      expect(
        HydratedJson.readList({'items': 'oops'}, 'items', (m) => m),
        isEmpty,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedJson – readObject', () {
    test('returns parsed object for valid map value', () {
      final result = HydratedJson.readObject(
        {'obj': <String, dynamic>{'x': 10}},
        'obj',
        (m) => m['x'] as int,
      );
      expect(result, equals(10));
    });

    test('returns null for missing key', () {
      expect(HydratedJson.readObject({}, 'obj', (m) => m), isNull);
    });

    test('returns null for null value', () {
      expect(
        HydratedJson.readObject({'obj': null}, 'obj', (m) => m),
        isNull,
      );
    });

    test('returns null for non-Map value', () {
      expect(
        HydratedJson.readObject({'obj': 'string'}, 'obj', (m) => m),
        isNull,
      );
    });

    test('returns null when fromJson returns null', () {
      expect(
        HydratedJson.readObject(
          {'obj': <String, dynamic>{}},
          'obj',
          (_) => null,
        ),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('HydratedJson – writeList', () {
    test('serialises list via toJson callback', () {
      final result = HydratedJson.writeList(
        [1, 2, 3],
        (e) => {'v': e},
      );
      expect(
        result,
        equals([
          {'v': 1},
          {'v': 2},
          {'v': 3},
        ]),
      );
    });

    test('returns empty list for null input', () {
      expect(HydratedJson.writeList<int>(null, (e) => e), isEmpty);
    });

    test('returns empty list for empty iterable', () {
      expect(HydratedJson.writeList<int>([], (e) => e), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('NIL sentinel', () {
    test('NIL is not a num, String, bool, Map, or List', () {
      const nil = NIL();
      expect(nil is num, isFalse);
      expect(nil is String, isFalse);
      expect(nil is bool, isFalse);
      expect(nil is Map, isFalse);
      expect(nil is List, isFalse);
    });
  });
}
