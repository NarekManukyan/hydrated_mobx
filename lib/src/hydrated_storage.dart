import 'dart:async';

import 'package:hive_ce/hive.dart';
// hive_ce does not expose HiveImpl through its public API (the class is marked
// "Not part of public API" and the global `Hive` is itself a HiveImpl). We need
// a *separate* instance so this package never conflicts with an app that calls
// `Hive.init` itself (https://github.com/hivedb/hive/issues/336), so importing
// the implementation directly is unavoidable. The dependency is pinned to a
// single major (`hive_ce: ^2`) to bound exposure to internal changes.
// ignore: implementation_imports
import 'package:hive_ce/src/hive_impl.dart';
import 'package:hydrated_mobx/src/hydrated_cipher.dart';
import 'package:hydrated_mobx/src/hydrated_mobx.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';

/// Interface which is used to persist and retrieve state changes.
///
/// Implementations must call [HydratedMobX.suspendAll] with themselves from
/// [clear] before wiping, so no live store writes its state back afterwards.
abstract class Storage {
  /// Returns the value for [key], or `null` when there is none.
  dynamic read(String key);

  /// Persists the [key]/[value] pair.
  Future<void> write(String key, dynamic value);

  /// Deletes the value for [key].
  Future<void> delete(String key);

  /// Deletes the values for every key in [keys] in one operation.
  Future<void> deleteAll(Iterable<String> keys);

  /// Every key currently stored, including the `.__version` keys
  /// [HydratedMobX] keeps beside versioned state
  /// (see [HydratedMobX.versionKeySuffix]).
  Iterable<String> get keys;

  /// Clears all key value pairs from storage.
  Future<void> clear();

  /// Closes the storage instance, freeing any allocated resources.
  /// A storage instance can no longer be used once it is closed.
  Future<void> close();
}

/// A [Storage] that records when each key was last used, for eviction.
///
/// [HydratedMobX] calls [markUsed] when a store hydrates from a key. A plain
/// [Storage.read] does not count as use, so tools that only display stored
/// values (inspectors, debug screens) do not keep keys from being evicted.
abstract class UseTrackingStorage implements Storage {
  /// Records that [key] was used now.
  void markUsed(String key);
}

/// {@template forwarding_storage}
/// A [Storage] that forwards every call to [inner]; extend it to wrap a
/// storage (to count, log or delay writes) and override what you need.
///
/// Stores bind to the wrapper, not to [inner], so [clear] suspends the
/// wrapper's stores before clearing [inner].
/// {@endtemplate}
class ForwardingStorage implements UseTrackingStorage {
  /// {@macro forwarding_storage}
  ForwardingStorage(this.inner);

  /// The storage every call is forwarded to.
  final Storage inner;

  @override
  dynamic read(String key) => inner.read(key);

  @override
  Future<void> write(String key, dynamic value) => inner.write(key, value);

  @override
  Future<void> delete(String key) => inner.delete(key);

  @override
  Future<void> deleteAll(Iterable<String> keys) => inner.deleteAll(keys);

  @override
  Iterable<String> get keys => inner.keys;

  @override
  void markUsed(String key) {
    final target = inner;
    if (target is UseTrackingStorage) target.markUsed(key);
  }

  @override
  Future<void> clear() {
    HydratedMobX.suspendAll(storage: this);
    return inner.clear();
  }

  @override
  Future<void> close() => inner.close();
}

/// Thrown when a [Storage] is used after [Storage.close].
class StorageClosedException implements Exception {
  /// Creates the exception for the operation that found storage closed.
  const StorageClosedException(this.operation);

  /// The operation attempted on the closed storage (`read`, `write`, ...).
  final String operation;

  @override
  String toString() =>
      'StorageClosedException: cannot $operation, the storage is closed.';
}

/// Decides when Hive compacts a box file, given its live [entries] and the
/// [deletedEntries] (overwritten or deleted frames) still in the file.
typedef HydratedCompactionStrategy = bool Function(
  int entries,
  int deletedEntries,
);

/// {@template hydrated_storage_directory}
/// A platform-agnostic storage directory representation.
/// {@endtemplate}
class HydratedStorageDirectory {
  /// {@macro hydrated_storage_directory}
  const HydratedStorageDirectory(this.path);

  /// The path to the storage directory.
  final String path;

  /// Sentinel directory used to determine that web storage should be used
  /// when initializing [HydratedStorage].
  ///
  /// ```dart
  /// await HydratedStorage.build(
  ///   storageDirectory: HydratedStorageDirectory.web,
  /// );
  /// ```
  static const web = HydratedStorageDirectory('');
}

/// {@template hydrated_storage}
/// Implementation of [Storage] which uses [package:hive_ce](https://pub.dev/packages/hive_ce)
/// to persist and retrieve state changes from the local device.
///
/// Each instance owns one Hive box, named by `boxName`. Build one per
/// namespace (e.g. a session box and an account box) and pass it to the
/// stores that belong there via `HydratedMobX(storage: ...)`; clearing one
/// namespace then never touches the other.
/// {@endtemplate}
class HydratedStorage implements UseTrackingStorage {
  /// Wraps an already-open [box] without eviction metadata.
  @visibleForTesting
  HydratedStorage(Box<dynamic> box) : this._(box, null, clock: DateTime.now);

  HydratedStorage._(
    this._box,
    this._meta, {
    required DateTime Function() clock,
    Duration useResolution = defaultUseResolution,
  })  : _clock = clock,
        _useResolution = useResolution;

  /// The box name used when none is given to [build].
  static const defaultBoxName = 'hydrated_box';

  /// Suffix of the companion box holding each key's last-use time.
  static const _metaBoxSuffix = '__meta';

  /// How often a key's use time is rewritten at most, by default.
  static const defaultUseResolution = Duration(minutes: 1);

  /// Returns an instance of [HydratedStorage].
  ///
  /// For web, use [HydratedStorageDirectory.web] as the [storageDirectory].
  ///
  /// ```dart
  /// HydratedMobX.storage = await HydratedStorage.build(
  ///   storageDirectory: kIsWeb
  ///       ? HydratedStorageDirectory.web
  ///       : HydratedStorageDirectory(
  ///           (await getApplicationSupportDirectory()).path,
  ///         ),
  /// );
  /// ```
  ///
  /// - [encryptionCipher] encrypts the box, e.g.
  ///   `HydratedAesCipher(sha256.convert(utf8.encode(password)).bytes)`.
  /// - [boxName] picks the box, so several storages can live side by side.
  /// - [maxAge] and [maxEntries] evict stale state once the box is open:
  ///   see [evict]. [evictable] limits eviction to the keys it accepts.
  /// - [trackUse] records use times without evicting at build, for a later
  ///   [evict]. It is implied by [maxAge] and [maxEntries]. Use times live in
  ///   a companion box and cost a small write when a key is used again after
  ///   [useResolution]; storages that never evict skip all of it. Keep the
  ///   setting the same across launches: keys written while it was off look
  ///   as old as their last recorded use. A use time can lag the real use by
  ///   up to [useResolution], so keep it well below [maxAge].
  /// - [compactionStrategy] overrides when Hive rewrites the box file.
  static Future<HydratedStorage> build({
    required HydratedStorageDirectory storageDirectory,
    HydratedCipher? encryptionCipher,
    String boxName = defaultBoxName,
    Duration? maxAge,
    int? maxEntries,
    bool Function(String key)? evictable,
    bool trackUse = false,
    Duration useResolution = defaultUseResolution,
    HydratedCompactionStrategy? compactionStrategy,
    @visibleForTesting DateTime Function() clock = DateTime.now,
  }) {
    if (boxName.endsWith(_metaBoxSuffix)) {
      throw ArgumentError.value(
        boxName,
        'boxName',
        'must not end with "$_metaBoxSuffix", which names use-time boxes',
      );
    }
    final lock = _buildLocks.putIfAbsent(
      '${storageDirectory.path}/$boxName',
      Lock.new,
    );
    return lock.synchronized(() async {
      final hive = HiveImpl();
      if (storageDirectory != HydratedStorageDirectory.web) {
        hive.init(storageDirectory.path);
      }
      final strategy = compactionStrategy ?? _defaultCompaction;
      Future<Box<dynamic>> open(String name) => hive.openBox<dynamic>(
            name,
            encryptionCipher: encryptionCipher,
            compactionStrategy: strategy,
          );
      final tracks = trackUse || maxAge != null || maxEntries != null;
      // A failed build closes what it opened, so the next build can open the
      // box files again.
      final boxes = await Future.wait(
        [open(boxName), if (tracks) open('$boxName$_metaBoxSuffix')],
        cleanUp: (box) => unawaited(box.close()),
      );
      final storage = HydratedStorage._(
        boxes.first,
        tracks ? boxes.last : null,
        clock: clock,
        useResolution: useResolution,
      );
      try {
        await storage._stampUntracked();
        if (maxAge != null || maxEntries != null) {
          await storage.evict(
            olderThan: maxAge,
            maxEntries: maxEntries,
            where: evictable,
          );
        }
      } catch (_) {
        await storage.close();
        rethrow;
      }
      return storage;
    });
  }

  /// Hive's own default (not exported): at least 60 dead frames making up
  /// over 15% of the file.
  static bool _defaultCompaction(int entries, int deletedEntries) =>
      deletedEntries > 60 && deletedEntries / entries > 0.15;

  /// One per box file, so building different boxes runs in parallel.
  static final _buildLocks = <String, Lock>{};

  final Box<dynamic> _box;

  /// Last-use time (ms since epoch) of each state key, for [evict].
  final Box<dynamic>? _meta;

  final DateTime Function() _clock;
  final Duration _useResolution;

  final _lock = Lock();

  void _checkOpen(String operation) {
    if (!_box.isOpen) throw StorageClosedException(operation);
  }

  /// Runs [body] under [_lock], checking the box is open both now and when
  /// its turn comes: a call queued behind [close] fails with
  /// [StorageClosedException], not Hive's own error.
  Future<void> _locked(String operation, Future<void> Function() body) {
    _checkOpen(operation);
    return _lock.synchronized(() {
      _checkOpen(operation);
      return body();
    });
  }

  // Unlike the mutating ops, read is not guarded by [_lock]: Hive's `get` is
  // a synchronous in-memory lookup that cannot interleave with a mutation on
  // Dart's single-threaded event loop.
  @override
  dynamic read(String key) {
    _checkOpen('read');
    return _box.get(key);
  }

  @override
  Iterable<String> get keys {
    _checkOpen('list keys');
    return _box.keys.whereType<String>();
  }

  @override
  Future<void> write(String key, dynamic value) {
    return _locked(
      'write',
      () => Future.wait([_box.put(key, value), _stamp(key)]),
    );
  }

  @override
  Future<void> delete(String key) => deleteAll([key]);

  @override
  Future<void> deleteAll(Iterable<String> keys) {
    _checkOpen('delete');
    final list = keys.toList();
    if (list.isEmpty) return Future.value();
    return _locked(
      'delete',
      () => Future.wait([
        _box.deleteAll(list),
        if (_meta case final meta?) meta.deleteAll(list),
      ]),
    );
  }

  @override
  Future<void> clear() {
    _checkOpen('clear');
    // Suspend this storage's live stores now, not when the lock frees up: a
    // write they queued meanwhile would land after the wipe.
    HydratedMobX.suspendAll(storage: this);
    return _locked('clear', () async {
      await Future.wait([
        _box.clear(),
        if (_meta case final meta?) meta.clear(),
      ]);
    });
  }

  @override
  Future<void> close() async {
    if (!_box.isOpen) return;
    return _lock.synchronized(
      () =>
          Future.wait([_box.close(), if (_meta case final meta?) meta.close()]),
    );
  }

  /// Deletes stale state, together with its `.__version` key.
  ///
  /// - [olderThan] drops every key not hydrated or written for that long.
  /// - [maxEntries] then keeps only that many keys, the most recently used.
  /// - [where] limits both to the keys it accepts; other keys are never
  ///   evicted and do not count towards [maxEntries].
  ///
  /// A key's use time has the resolution given to [build]. Keys written before
  /// eviction metadata existed count as used when the storage was built.
  ///
  /// Live stores of evicted keys stop persisting, as with
  /// [HydratedMobX.clearAll]. Does nothing unless the storage was built to
  /// track use (`trackUse`, `maxAge` or `maxEntries`).
  Future<void> evict({
    Duration? olderThan,
    int? maxEntries,
    bool Function(String key)? where,
  }) async {
    if (maxEntries != null && maxEntries < 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be >= 0');
    }
    final meta = _meta;
    if (meta == null) {
      _checkOpen('evict');
      return;
    }
    // Let use times already queued by [markUsed] land first, or a key used
    // just now could be judged by its previous use time.
    await _locked('evict', () async {});
    final now = _clock().millisecondsSinceEpoch;
    final candidates = [
      for (final key in keys)
        if (!HydratedMobX.isVersionKey(key) && (where?.call(key) ?? true))
          (key: key, usedAt: _usedAt(meta, key) ?? now),
    ];
    final doomed = <String>{};
    if (olderThan != null) {
      final cutoff = now - olderThan.inMilliseconds;
      doomed.addAll([
        for (final c in candidates)
          if (c.usedAt < cutoff) c.key,
      ]);
    }
    if (maxEntries != null) {
      final kept = [
        for (final c in candidates)
          if (!doomed.contains(c.key)) c,
      ]..sort((a, b) => b.usedAt.compareTo(a.usedAt));
      doomed.addAll(kept.skip(maxEntries).map((c) => c.key));
    }
    if (doomed.isEmpty) return;
    // The shared path: suspends live stores of doomed keys and deletes their
    // version keys too.
    await HydratedMobX.clearAll(storage: this, where: doomed.contains);
  }

  static int? _usedAt(Box<dynamic> meta, String key) {
    final value = meta.get(key);
    return value is int ? value : null;
  }

  /// Gives every key without a use time one, so state written before
  /// eviction metadata existed is aged from now rather than evicted at once.
  Future<void> _stampUntracked() async {
    final meta = _meta;
    if (meta == null) return;
    final now = _clock().millisecondsSinceEpoch;
    final untracked = {
      for (final key in keys)
        if (!HydratedMobX.isVersionKey(key) && !meta.containsKey(key)) key: now,
    };
    if (untracked.isNotEmpty) await meta.putAll(untracked);
  }

  /// Whether [key]'s use time is due to be rewritten: it is a state key and
  /// was not recorded within the use resolution.
  bool _dueStamp(Box<dynamic> meta, String key) {
    if (HydratedMobX.isVersionKey(key)) return false;
    final last = _usedAt(meta, key);
    return last == null ||
        _clock().millisecondsSinceEpoch - last >= _useResolution.inMilliseconds;
  }

  /// Records [key]'s use time when [_dueStamp]. Caller holds [_lock].
  Future<void> _stamp(String key) async {
    final meta = _meta;
    if (meta == null || !meta.isOpen || !_dueStamp(meta, key)) return;
    await meta.put(key, _clock().millisecondsSinceEpoch);
  }

  @override
  void markUsed(String key) {
    final meta = _meta;
    if (meta == null || !meta.isOpen || !_dueStamp(meta, key)) return;
    // Best effort: a lost use time only makes the key look older.
    unawaited(_lock.synchronized(() => _stamp(key)).catchError((Object _) {}));
  }
}
