// ignore_for_file: avoid_catching_errors

import 'dart:async';
import 'dart:developer';

import 'package:hydrated_mobx/src/hydrated_storage.dart';
import 'package:hydrated_mobx/src/plain_json.dart';
import 'package:meta/meta.dart';
import 'package:mobx/mobx.dart';

/// {@template hydrated_mobx}
/// An abstract class which enables automatic state persistence for classes
/// using [Store]. State can be persisted across hot restarts and app restarts.
///
/// To use HydratedMobX, extend this class and implement:
/// - [storagePrefix] - a fixed name for the store's key on disk
/// - [toJson] - converts the store state to a JSON representation
/// - [fromJson] - restores the store state from a JSON representation
///
/// Example:
/// ```dart
/// class CounterStore extends HydratedMobX with Store {
///   CounterStore() : super();
///
///   @observable
///   int count = 0;
///
///   @action
///   void increment() => count++;
///
///   @override
///   String get storagePrefix => 'counter';
///
///   @override
///   Map<String, dynamic>? toJson() => {'count': count};
///
///   @override
///   void fromJson(Map<String, dynamic> json) {
///     count = json['count'] as int;
///   }
/// }
/// ```
///
/// The store hydrates in its constructor, before the subclass constructor
/// body runs, so [fromJson] and [toJson] may only use fields assigned by
/// initializers (`this.x` parameters, field initializers, initializer lists).
///
/// The store then persists its state whenever it changes: right away, or
/// coalesced over `persistDelay` when one is set. A change that leaves
/// [toJson] equal to what was last written is not written again.
/// {@endtemplate}
abstract class HydratedMobX with Store {
  /// Creates a new instance and hydrates its state.
  ///
  /// - [storeId] gives one instance its own key, e.g. per conversation.
  /// - [storage] binds the store to a storage other than the global
  ///   [HydratedMobX.storage], e.g. a second namespace or a test double.
  /// - [onHydrationError] and [onStorageError] handle this store's failures;
  ///   when omitted, [HydratedMobX.observer] handles them.
  /// - [persistDelay] coalesces the writes of changes made within that window
  ///   into one; defaults to [HydratedMobX.defaultPersistDelay].
  HydratedMobX({
    String? storeId,
    Storage? storage,
    OnHydrationError? onHydrationError,
    OnStorageError? onStorageError,
    Duration? persistDelay,
  })  : _constructorStorageId = storeId,
        _persistDelay = persistDelay,
        _onHydrationError = onHydrationError,
        _onStorageError = onStorageError {
    hydrate(storage: storage);
  }

  // ---------------------------------------------------------------------------
  // Global configuration
  // ---------------------------------------------------------------------------

  static Storage? _storage;

  /// Sets the [Storage] that stores use when none is passed to them.
  static set storage(Storage? storage) => _storage = storage;

  /// The [Storage] that stores use when none is passed to them.
  static Storage get storage {
    if (_storage == null) throw const StorageNotFound();
    return _storage!;
  }

  /// Handles hydration and persistence failures of every store that was not
  /// given its own handler. Set it once at startup, e.g. to forward errors to
  /// a crash reporter.
  static HydratedObserver observer = const HydratedObserver();

  /// The `persistDelay` of a store constructed without one.
  ///
  /// [Duration.zero] (the default) writes each change right away.
  static Duration defaultPersistDelay = Duration.zero;

  /// Suffix appended to a [storageToken] to form the key under which the
  /// persisted schema [version] is stored.
  static const versionKeySuffix = '.__version';

  /// The key holding the schema version of the state stored under [token].
  static String versionKeyOf(String token) => '$token$versionKeySuffix';

  /// Whether [key] holds a schema version rather than state.
  static bool isVersionKey(String key) => key.endsWith(versionKeySuffix);

  /// The [storageToken] a raw storage [key] belongs to: the key itself, or
  /// the token a version key was stamped for.
  static String tokenOfKey(String key) => isVersionKey(key)
      ? key.substring(0, key.length - versionKeySuffix.length)
      : key;

  // ---------------------------------------------------------------------------
  // Global operations
  // ---------------------------------------------------------------------------

  /// Seeds [storage] (the global one by default) with pre-existing [data]
  /// imported from another persistence layer (e.g. `SharedPreferences`, a
  /// legacy Hive box, or a previous key scheme).
  ///
  /// [data] maps each [storageToken] to the JSON a store of that token should
  /// hydrate from, so keys follow the same `'$storagePrefix${storeId ?? id}'`
  /// composition.
  ///
  /// [version] is the schema version the imported payloads are already in; it
  /// is recorded so that a store whose [HydratedMobX.version] is higher does
  /// **not** re-run [migrate] against data that is already current. Leave it at
  /// the default (`1`) when importing legacy version-1 data that should be
  /// migrated forward.
  ///
  /// Existing keys are left untouched unless [overwrite] is `true`.
  ///
  /// Call this before constructing the stores that should pick the data up.
  static Future<void> importData(
    Map<String, Map<String, dynamic>> data, {
    bool overwrite = false,
    int version = 1,
    Storage? storage,
  }) async {
    final target = storage ?? HydratedMobX.storage;
    // From the keys, not by reading each value: a read decodes it, and one
    // that does not decode would stop the import, even one meant to
    // overwrite it.
    final present = target.keys.toSet();
    for (final entry in data.entries) {
      final existing = present.contains(entry.key);
      if (!overwrite && existing) continue;
      // Old state goes, then the version, then the new state: an interruption
      // leaves nothing to hydrate, which is harmless, never state under a
      // version it was not written in.
      if (existing) await target.delete(entry.key);
      final versionKey = versionKeyOf(entry.key);
      if (version > 1) {
        await target.write(versionKey, version);
      } else {
        // An absent key reads as version 1; drop one a newer build stamped.
        await target.delete(versionKey);
      }
      await target.write(entry.key, entry.value);
    }
  }

  /// Moves stored state to new tokens, e.g. after renaming a
  /// [storagePrefix] or leaving 1.x's `runtimeType` keys (see
  /// `LegacyTokens`).
  ///
  /// [to] is asked for the new token of every state key in [storage] (the
  /// global one by default); `null` or the same key leaves it where it is.
  /// It gets the stored value as a function, so a key it rejects by name is
  /// never read (from a `FileStorage`, a read is a file read). A key that
  /// moves is read again for the move, so one value at a time is held. The
  /// state moves with its version key. Returns the moves made, old token to
  /// new.
  ///
  /// No state is overwritten. A move is skipped when:
  /// - the new token already holds different state, or the same state under
  ///   another version;
  /// - two keys would move to the same token;
  /// - the new token is itself moving away in this run (A to B while B moves
  ///   to C): B could hold the state A's move expects, and A would be
  ///   deleted. The next run, with B moved, finishes it;
  /// - a live store uses either token, since it would not see the move.
  ///
  /// When the new token already holds the same state under the same
  /// version, only the old key is deleted; that is how an interrupted run
  /// finishes. A version key left at the new token without its state is
  /// replaced.
  ///
  /// A key that fails, in [to] (by throwing or by returning a version key)
  /// or in its move, stays where it is, and the others still move. Each
  /// failure goes to [onError]; without it, the first one is rethrown once
  /// every key has been tried.
  ///
  /// Each move writes the version, then the state, then deletes the old
  /// keys, so it is safe to run again after a crash. Call it at startup,
  /// before constructing the stores.
  static Future<Map<String, String>> moveTokens(
    String? Function(String token, Object? Function() value) to, {
    Storage? storage,
    void Function(String token, Object error, StackTrace stackTrace)? onError,
  }) async {
    final target = storage ?? HydratedMobX.storage;
    // Unwrapped, so a store bound to the inner storage of a wrapper counts.
    final live = liveTokens(storage: _unwrapped(target));
    final existing = target.keys.toSet();
    final planned = <String, String>{};
    final targets = <String>{};
    final clashing = <String>{};
    final failures = _Failures(onError);
    for (final key in existing) {
      if (isVersionKey(key) || live.contains(key)) continue;
      // Read at most once per call of [to], and not kept after it: holding
      // every value read would hold every decoded state at once, which an
      // encoded box or a FileStorage exists to avoid.
      Object? value;
      var read = false;
      final String? next;
      try {
        next = to(key, () {
          if (!read) {
            value = target.read(key);
            read = true;
          }
          return value;
        });
      } catch (error, stackTrace) {
        failures.add(key, error, stackTrace);
        continue;
      }
      if (next == null || next == key || live.contains(next)) continue;
      if (isVersionKey(next)) {
        failures.add(
          key,
          ArgumentError.value(next, 'to', 'returned a version key'),
          StackTrace.current,
        );
        continue;
      }
      if (!targets.add(next)) clashing.add(next);
      planned[key] = next;
    }
    final moved = <String, String>{};
    for (final MapEntry(key: from, value: next) in planned.entries) {
      if (clashing.contains(next) || planned.containsKey(next)) continue;
      try {
        final done = await _moveOne(
          source: target,
          from: from,
          value: target.read(from),
          target: target,
          to: next,
          exists: existing.contains(next),
        );
        if (done) moved[from] = next;
      } catch (error, stackTrace) {
        failures.add(from, error, stackTrace);
      }
    }
    failures.rethrowFirst();
    return moved;
  }

  /// Moves the state [value] of token [from] in [source] to token [to] in
  /// [target], with its version key and use time, and returns whether it
  /// did. [exists] says whether [target] holds [to] already; then only the
  /// same state under the same version counts as moved, and is deleted from
  /// [source]. A [value] of `null` is nothing to move.
  ///
  /// Writes the version, then the state, then deletes [from], so a crash
  /// leaves the state in one place or both, and running again finishes. A
  /// failed write takes back what it wrote to [to] before rethrowing.
  static Future<bool> _moveOne({
    required Storage source,
    required String from,
    required Object? value,
    required Storage target,
    required String to,
    required bool exists,
  }) async {
    // Gone since the keys were listed: deleted, or behind a queued delete.
    if (value == null) return false;
    final fromVersion = versionKeyOf(from);
    final toVersion = versionKeyOf(to);
    final version = source.read(fromVersion);
    if (exists) {
      if (!_jsonEquals(target.read(to), value) ||
          target.read(toVersion) != version) {
        return false;
      }
      // A run that stopped after the state write left [to] the time of
      // that write.
      await _carryUseTime(source, from, target, to);
    } else {
      try {
        if (version != null) {
          await target.write(toVersion, version);
        } else {
          // An absent key reads as version 1; drop one left behind.
          await target.delete(toVersion);
        }
        await target.write(to, value);
      } catch (_) {
        // A version key on its own would date state written there later.
        await Future.sync(() => target.deleteAll([to, toVersion]))
            .catchError((Object _) {});
        rethrow;
      }
      await _carryUseTime(source, from, target, to);
    }
    await source.deleteAll([from, fromVersion]);
    return true;
  }

  /// Gives [to] in [target] the use time of [from] in [source], when both
  /// keep use times. Best effort, like every use time: the state is already
  /// in [target], and failing the move now would leave it in both storages,
  /// so a use time that cannot be carried only makes [to] look used at the
  /// move.
  static Future<void> _carryUseTime(
    Storage source,
    String from,
    Storage target,
    String to,
  ) async {
    if (source is UseTimeStorage && target is UseTimeStorage) {
      try {
        if (source.usedAt(from) case final usedAt?) {
          await target.setUsedAt(to, usedAt);
        }
      } on Object {
        // See above.
      }
    }
  }

  /// Moves the state of every token that passes [where] from storage [from]
  /// into [to], with its version key and, between storages that keep them
  /// ([UseTimeStorage]), its use time, e.g. per-document state from a Hive
  /// box into a `FileStorage`. Returns the tokens moved.
  ///
  /// A token [to] already holds with different state, or with the same
  /// state under another version, stays in [from]; one it holds with the
  /// same state and version is only deleted from [from]. Tokens of live
  /// stores bound to either storage are skipped.
  ///
  /// A token that fails, in [where] or in its move, stays in [from], and the
  /// others still move. Each failure goes to [onError]; without it, the
  /// first one is rethrown once every token has been tried.
  ///
  /// Each token is written to [to] (version, then state) before it is
  /// deleted from [from], so a crash leaves it in one storage or both, never
  /// in neither, and running again finishes the move. Call it at startup,
  /// before constructing the stores.
  ///
  /// Throws an [ArgumentError] when [from] and [to] are the same storage,
  /// also when one wraps the other ([ForwardingStorage]): the move would
  /// delete every token it wrote.
  static Future<Set<String>> transferTokens({
    required Storage from,
    required Storage to,
    required bool Function(String token) where,
    void Function(String token, Object error, StackTrace stackTrace)? onError,
  }) async {
    if (identical(_unwrapped(from), _unwrapped(to))) {
      throw ArgumentError.value(to, 'to', 'is the same storage as from');
    }
    // Unwrapped, so a store bound to the inner storage of a wrapper counts.
    final live = {
      ...liveTokens(storage: _unwrapped(from)),
      ...liveTokens(storage: _unwrapped(to)),
    };
    final targetKeys = to.keys.toSet();
    final moved = <String>{};
    final failures = _Failures(onError);
    final tokens = [
      for (final key in from.keys)
        if (!isVersionKey(key) && !live.contains(key)) key,
    ];
    for (final token in tokens) {
      try {
        if (!where(token)) continue;
        final done = await _moveOne(
          source: from,
          from: token,
          value: from.read(token),
          target: to,
          to: token,
          exists: targetKeys.contains(token),
        );
        if (done) moved.add(token);
      } catch (error, stackTrace) {
        failures.add(token, error, stackTrace);
      }
    }
    failures.rethrowFirst();
    return moved;
  }

  /// The storage [storage] writes into, through any [ForwardingStorage]s.
  static Storage _unwrapped(Storage storage) => switch (storage) {
        final ForwardingStorage wrapper => _unwrapped(wrapper.inner),
        _ => storage,
      };

  /// Wipes persisted state from [storage] (the global one by default).
  ///
  /// Every live store bound to [storage] whose [storageToken] passes [where]
  /// (all of them when [where] is `null`) stops persisting first, so none of
  /// them writes its state back, and any write it had pending is dropped.
  ///
  /// - With [where] `null`, the whole storage is cleared.
  /// - Otherwise only the keys whose token passes [where] are deleted, with
  ///   their version keys, in one call of [Storage.deleteAll], which is as
  ///   atomic as that storage makes it; every other key is left untouched.
  ///   Keys that no store owns are tested by their raw name.
  ///
  /// With [resume] `true`, the suspended stores start persisting again
  /// afterwards and write their current state back.
  static Future<void> clearAll({
    Storage? storage,
    bool Function(String token)? where,
    bool resume = false,
  }) async {
    final target = storage ?? HydratedMobX.storage;
    final affected = [
      for (final store in _live(target))
        if (where == null || where(store.storageToken)) store,
    ];
    for (final store in affected) {
      store._suspend();
    }
    if (where == null) {
      await target.clear();
    } else {
      await target.deleteAll([
        for (final key in target.keys)
          if (where(tokenOfKey(key))) key,
      ]);
    }
    if (resume) {
      for (final store in affected) {
        if (store._selfRef != null) store._startPersisting();
      }
    }
  }

  /// Deletes the state stored under [token], and its version key, from
  /// [storage] (the global one by default). A live store with that token
  /// stops persisting.
  static Future<void> deleteToken(String token, {Storage? storage}) =>
      clearAll(storage: storage, where: (t) => t == token);

  /// Writes the pending state of every live store bound to [storage] (all
  /// stores when `null`) now, instead of when its `persistDelay` ends.
  ///
  /// Call it when the app goes to the background, so a coalesced change is
  /// not lost if the process is killed there.
  static Future<void> flushAll({Storage? storage}) =>
      Future.wait([for (final store in _live(storage)) store.flush()]);

  /// The [storageToken]s of the live stores bound to [storage] (all stores
  /// when `null`): constructed and not yet disposed or collected.
  static Set<String> liveTokens({Storage? storage}) =>
      {for (final store in _live(storage)) store.storageToken};

  /// Moves every live store bound to [from] onto [to], e.g. after closing a
  /// storage and building it again. Their state is not read again; each
  /// store writes its current state to [to] on its next change.
  ///
  /// Call [flushAll] for [from] before closing it, so no pending write is
  /// lost.
  ///
  /// [to] built with `maxAge` or `maxEntries` evicts before the stores move
  /// over, so a store whose key it evicted would write it back. Build [to]
  /// without them (with `trackUse: true` for a [HydratedStorage]), rebind,
  /// then call `evict`.
  static void rebindAll({required Storage from, required Storage to}) {
    for (final store in _live(from, throughWrappers: false)) {
      store
        .._boundStorage = to
        .._forgetPersisted();
    }
  }

  /// Stops every live store bound to [storage] (all stores when `null`) from
  /// persisting and drops its pending write.
  ///
  /// A [Storage] implementation calls this with itself from [Storage.clear]
  /// before wiping, so no store writes cleared state back.
  static void suspendAll({Storage? storage}) {
    for (final store in _live(storage)) {
      store._suspend();
    }
  }

  /// Registry of live instances, so storage-wide operations can reach every
  /// store's persistence reaction.
  ///
  /// Entries are [WeakReference]s so the registry never keeps a store alive on
  /// its own: a persisting store is kept reachable by its MobX reaction, and
  /// once that is disposed the store can be collected and [_finalizer] prunes
  /// its entry.
  static final Set<WeakReference<HydratedMobX>> _instances =
      <WeakReference<HydratedMobX>>{};

  static final Finalizer<WeakReference<HydratedMobX>> _finalizer =
      Finalizer<WeakReference<HydratedMobX>>(_instances.remove);

  /// State writes whose version stamp has not landed yet, by storage and
  /// token. A storage shows a write from the moment it is called, but the
  /// stamp is written only once the state has landed, so a store built in
  /// between would read the new state under the old version and migrate it
  /// again. Kept under the storage at the bottom of any wrappers, which
  /// every store writing into it reads through.
  static final _stamping =
      Expando<Map<String, List<({Object json, int version})>>>();

  /// Live stores bound to [storage], or all of them when it is `null`.
  /// With [throughWrappers], a store bound to a [ForwardingStorage] that
  /// wraps [storage] counts too, since it writes into [storage].
  /// Prunes dead registry entries along the way.
  static List<HydratedMobX> _live(
    Storage? storage, {
    bool throughWrappers = true,
  }) {
    bool writesInto(Storage? bound) {
      for (var s = bound; s != null;) {
        if (identical(s, storage)) return true;
        s = throughWrappers && s is ForwardingStorage ? s.inner : null;
      }
      return false;
    }

    final live = <HydratedMobX>[];
    _instances.removeWhere((ref) {
      final store = ref.target;
      if (store == null) return true;
      if (storage == null || writesInto(store._boundStorage)) live.add(store);
      return false;
    });
    return live;
  }

  // ---------------------------------------------------------------------------
  // Instance state
  // ---------------------------------------------------------------------------

  final String? _constructorStorageId;
  final Duration? _persistDelay;
  OnHydrationError? _onHydrationError;
  OnStorageError? _onStorageError;

  /// The storage this store is bound to; set by the first [hydrate].
  Storage? _boundStorage;

  WeakReference<HydratedMobX>? _selfRef;
  ReactionDisposer? _persistDisposer;
  int _clearGeneration = 0;
  HydrationErrorBehavior _behavior = HydrationErrorBehavior.overwrite;

  /// The schema [version] recorded on disk for this store, so the version key
  /// is stamped once (after the state write) rather than on every change.
  /// `null` means no version has been recorded yet.
  int? _lastStampedVersion;

  /// The JSON last written or hydrated, to skip writing an unchanged state.
  /// `null` when the next run must write.
  Object? _lastPersisted;

  /// The persistence run waiting for `persistDelay` to end, and its timer.
  ({Timer timer, void Function() run})? _pending;

  /// Completes when the latest write has finished, successfully or not.
  Future<void> _lastWrite = Future<void>.value();

  /// Deep equality of two JSON values that stops at the first difference.
  /// Cheaper than a general deep equality: map order is ignored only by
  /// looking keys up, never by hashing whole collections.
  static bool _jsonEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final MapEntry(:key, :value) in a.entries) {
        if (!b.containsKey(key) || !_jsonEquals(value, b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  void _register() {
    if (_selfRef != null) return;
    final ref = _selfRef = WeakReference<HydratedMobX>(this);
    _instances.add(ref);
    _finalizer.attach(this, ref, detach: this);
  }

  /// Stops persisting ahead of a wipe: drops the reaction and the pending
  /// run, and bumps the clear generation so any in-flight write (state or
  /// version) scheduled before the wipe is discarded.
  void _suspend() {
    _clearGeneration++;
    _stopPersisting();
    _forgetPersisted();
  }

  /// Drops the persistence reaction and its pending run.
  void _stopPersisting() {
    _cancelPending();
    _persistDisposer?.call();
    _persistDisposer = null;
  }

  /// Forgets what is on disk, so the next run writes (and stamps) again.
  void _forgetPersisted() {
    _lastStampedVersion = null;
    _lastPersisted = null;
  }

  void _cancelPending() {
    _pending?.timer.cancel();
    _pending = null;
  }

  void _reportStorageError(Object error, StackTrace stackTrace) {
    final handler = _onStorageError;
    if (handler != null) {
      handler(error, stackTrace);
    } else {
      observer.onStorageError(this, error, stackTrace);
    }
  }

  HydrationErrorBehavior _reportHydrationError(
    Object error,
    StackTrace stackTrace,
  ) {
    final handler = _onHydrationError;
    return handler != null
        ? handler(error, stackTrace)
        : observer.onHydrationError(this, error, stackTrace);
  }

  // ---------------------------------------------------------------------------
  // Hydration and persistence
  // ---------------------------------------------------------------------------

  /// Reads this store's state from storage and starts persisting changes.
  /// The constructor calls it; call it again to re-read the stored state.
  ///
  /// [storage] rebinds the store; otherwise it keeps the storage it was bound
  /// to. [onHydrationError] and [onStorageError] replace the store's
  /// handlers when given.
  ///
  /// When hydration fails, the [HydrationErrorBehavior] returned by the
  /// hydration error handler decides whether later changes overwrite the
  /// stored state ([HydrationErrorBehavior.overwrite], default) or leave it
  /// ([HydrationErrorBehavior.retain]) until a later successful [hydrate].
  /// A [fromJson] that throws part-way leaves the fields it already set.
  void hydrate({
    Storage? storage,
    OnHydrationError? onHydrationError,
    OnStorageError? onStorageError,
  }) {
    if (isVersionKey(storageToken)) {
      throw ArgumentError.value(
        storageToken,
        'storageToken',
        'must not end with the reserved "$versionKeySuffix"',
      );
    }
    final target =
        _boundStorage = storage ?? _boundStorage ?? HydratedMobX.storage;
    if (onHydrationError != null) _onHydrationError = onHydrationError;
    if (onStorageError != null) _onStorageError = onStorageError;
    _register();
    _behavior = HydrationErrorBehavior.overwrite;
    _forgetPersisted();
    // Untracked: hydrating inside a widget build or another reaction must
    // not make that caller depend on the storage or the observer.
    untracked(() => _readStored(target));
    _startPersisting();
  }

  void _readStored(Storage target) {
    try {
      // The persistence run stamps [version] only after the state that
      // produced it has been written, so the version never leads the state;
      // [_restore] reads state whose stamp is still to come as that version.
      final rawVersion = target.read(_versionToken);
      if (rawVersion != null && rawVersion is! int) {
        log(
          'Persisted version for "$storageToken" is not an int ($rawVersion); '
          'treating the data as unversioned.',
          name: 'HydratedMobx',
        );
      }
      _lastStampedVersion = rawVersion is int ? rawVersion : null;
      final Object? stored = target.read(storageToken);
      if (stored != null) {
        if (target is UseTrackingStorage) target.markUsed(storageToken);
        _restore(target, stored);
      }
    } catch (error, stackTrace) {
      _behavior = _reportHydrationError(error, stackTrace);
    }
  }

  void _restore(Storage target, Object stored) {
    if (stored is! Map) {
      throw FormatException(
        'Persisted state for "$storageToken" is not a map',
        stored.runtimeType.toString(),
      );
    }
    // Data written before schema versioning existed has no version key and
    // is treated as version 1.
    final storedVersion =
        _stampingVersion(target, stored) ?? _lastStampedVersion ?? 1;
    Map<String, dynamic>? json = plainJson(stored)! as Map<String, dynamic>;
    if (storedVersion < version) {
      json = migrate(storedVersion, json);
      if (json == null) {
        _discard(target);
        _notifyMigrated(storedVersion);
        return;
      }
    } else if (storedVersion > version) {
      log(
        'Persisted schema version $storedVersion for "$storageToken" is '
        'newer than the current version $version; loading without '
        'migration. Data may not match the current schema.',
        name: 'HydratedMobx',
      );
    }
    fromJson(json);
    // The storage's own value, not the copy fromJson may keep and mutate.
    if (storedVersion == version) _lastPersisted = stored;
    if (storedVersion < version) _notifyMigrated(storedVersion);
  }

  /// The version [stored] is about to be stamped with, when it is the state
  /// of a write into [target], or the storage it wraps, whose stamp has not
  /// landed yet.
  int? _stampingVersion(Storage target, Object stored) {
    final writes = _stamping[_unwrapped(target)]?[storageToken];
    if (writes == null) return null;
    for (final write in writes.reversed) {
      if (_jsonEquals(write.json, stored)) return write.version;
    }
    return null;
  }

  /// Records that [json] is being written to [target] with a version stamp
  /// to follow, and returns the function that forgets it again.
  void Function() _startStamp(Storage target, Map<String, dynamic> json) {
    final write = (json: json as Object, version: version);
    final token = storageToken;
    final storage = _unwrapped(target);
    final byToken = _stamping[storage] ??= {};
    (byToken[token] ??= []).add(write);
    return () {
      final writes = byToken[token]!..remove(write);
      if (writes.isNotEmpty) return;
      byToken.remove(token);
      if (byToken.isEmpty && identical(_stamping[storage], byToken)) {
        _stamping[storage] = null;
      }
    };
  }

  /// Tells the observer, once the store holds the migrated state; a failing
  /// observer must not turn a good hydration into a failed one.
  void _notifyMigrated(int fromVersion) {
    try {
      observer.onMigrate(this, fromVersion, version);
    } catch (error, stackTrace) {
      _reportStorageError(error, stackTrace);
    }
  }

  /// Deletes stored state that [migrate] chose not to carry forward.
  void _discard(Storage target) {
    _lastStampedVersion = null;
    unawaited(
      Future.sync(() => target.deleteAll([storageToken, _versionToken]))
          .catchError(_reportStorageError),
    );
  }

  /// Arms the MobX reaction that persists state changes.
  ///
  /// Disposes any previous reaction first, so re-arming never leaks one or
  /// writes twice. Each reaction captures the clear generation active when
  /// it was armed, so a write scheduled before a clear is dropped rather than
  /// resurrecting cleared state.
  void _startPersisting() {
    _stopPersisting();
    final generation = _clearGeneration;
    final delay = _persistDelay ?? defaultPersistDelay;
    _persistDisposer = autorun(
      (_) => _persist(generation),
      name: 'HydratedMobX.persist($storageToken)',
      scheduler: delay > Duration.zero ? (run) => _schedule(run, delay) : null,
    );
  }

  Timer _schedule(void Function() run, Duration delay) {
    final timer = Timer(delay, () {
      _pending = null;
      run();
    });
    _pending = (timer: timer, run: run);
    return timer;
  }

  void _persist(int generation) {
    if (_behavior == HydrationErrorBehavior.retain) return;
    final Map<String, dynamic> json;
    try {
      final raw = toJson();
      if (raw == null) return;
      json = trustToJson ? raw : _toJson(raw);
    } catch (error, stackTrace) {
      // Caught here rather than by MobX, which would wrap it.
      untracked(() => _reportStorageError(error, stackTrace));
      return;
    }
    // Only versioned stores (version > 1) record a version key; an absent
    // key reads back as version 1.
    final stamp = version > 1 && _lastStampedVersion != version;
    if (!stamp && _jsonEquals(_lastPersisted, json)) return;
    _lastPersisted = json;
    // Untracked: a storage or error handler that reads observables must not
    // become a dependency of (or loop) this reaction.
    _lastWrite = untracked(() => _write(generation, json, stamp: stamp));
  }

  Future<void> _write(
    int generation,
    Map<String, dynamic> json, {
    required bool stamp,
  }) {
    final target = _boundStorage!;
    var done = Future.sync(() => target.write(storageToken, json));
    if (stamp) {
      final stamped = _startStamp(target, json);
      // Stamp the version only after the state write succeeds, so a failure
      // or crash leaves the version behind the state (which re-runs
      // migration) rather than ahead of it (which would skip one).
      done = done.then((_) {
        // A clear may have run (bumping the generation and deleting the
        // version key) while this was pending; don't resurrect the key.
        if (generation != _clearGeneration) return null;
        return target.write(_versionToken, version).then((_) {
          // Flip only once written, so a failed stamp is retried by the next
          // change, and not after a clear that reset it meanwhile.
          if (generation == _clearGeneration) _lastStampedVersion = version;
        });
      }).whenComplete(stamped);
    }
    return done.catchError((Object error, StackTrace stackTrace) {
      // Write the same state again on the next run.
      if (identical(_lastPersisted, json)) _lastPersisted = null;
      _reportStorageError(error, stackTrace);
    });
  }

  /// Writes the pending state now, when a `persistDelay` is holding it back,
  /// and completes when the latest write has finished. Write errors go to the
  /// storage error handler, not to the returned future.
  Future<void> flush() {
    final run = _pending?.run;
    if (run != null) {
      _cancelPending();
      run();
    }
    return _lastWrite;
  }

  // ---------------------------------------------------------------------------
  // JSON traversal
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _toJson(Map<String, dynamic> json) {
    try {
      return _traverseWrite(json) as Map<String, dynamic>;
    } finally {
      // A failed walk leaves the objects it was inside of behind.
      _seen.clear();
    }
  }

  dynamic _traverseWrite(Object? value) {
    final dynamic traversedAtomicJson = _traverseAtomicJson(value);
    if (traversedAtomicJson is! NIL) return traversedAtomicJson;
    final dynamic traversedComplexJson = _traverseComplexJson(value);
    if (traversedComplexJson is! NIL) return traversedComplexJson;
    try {
      _checkCycle(value);
      final dynamic customJson = _toEncodable(value);
      final dynamic traversedCustomJson = _traverseJson(customJson);
      if (traversedCustomJson is NIL) {
        throw HydratedUnsupportedError(value);
      }
      _removeSeen(value);
      return traversedCustomJson;
    } on HydratedCyclicError catch (e) {
      throw HydratedUnsupportedError(value, cause: e);
    } on HydratedUnsupportedError {
      rethrow;
    } catch (e) {
      throw HydratedUnsupportedError(value, cause: e);
    }
  }

  dynamic _traverseAtomicJson(dynamic object) {
    if (object is num) {
      if (!object.isFinite) return const NIL();
      return object;
    } else if (identical(object, true)) {
      return true;
    } else if (identical(object, false)) {
      return false;
    } else if (object == null) {
      return null;
    } else if (object is String) {
      return object;
    }
    return const NIL();
  }

  dynamic _traverseComplexJson(dynamic object) {
    if (object is List) {
      // Always a new list: the result is kept to compare the next state
      // with, so it must not alias a list the store may still mutate.
      if (object.isEmpty) return <dynamic>[];
      _checkCycle(object);
      final list = <dynamic>[
        for (final item in object) _traverseWrite(item),
      ];
      _removeSeen(object);
      return list;
    } else if (object is Map) {
      _checkCycle(object);
      final map = <String, dynamic>{};
      object.forEach((dynamic key, dynamic value) {
        if (key is String) map[key] = _traverseWrite(value);
      });
      _removeSeen(object);
      return map;
    }
    return const NIL();
  }

  dynamic _traverseJson(dynamic object) {
    final dynamic traversedAtomicJson = _traverseAtomicJson(object);
    return traversedAtomicJson is! NIL
        ? traversedAtomicJson
        : _traverseComplexJson(object);
  }

  // ignore: avoid_dynamic_calls
  dynamic _toEncodable(dynamic object) => object.toJson();

  final _seen = <dynamic>[];

  void _checkCycle(Object? object) {
    for (var i = 0; i < _seen.length; i++) {
      if (identical(object, _seen[i])) {
        throw HydratedCyclicError(object);
      }
    }
    _seen.add(object);
  }

  void _removeSeen(dynamic object) {
    assert(_seen.isNotEmpty, 'seen must not be empty');
    assert(identical(_seen.last, object), 'last seen object must be identical');
    _seen.removeLast();
  }

  // ---------------------------------------------------------------------------
  // Overridable API
  // ---------------------------------------------------------------------------

  /// [id] is used to uniquely identify multiple instances
  /// of the same store type.
  /// In most cases it is not necessary;
  /// however, if you wish to intentionally have multiple instances
  /// of the same store, then you must override [id]
  /// and return a unique identifier for each store instance
  /// in order to keep the caches independent of each other.
  String get id => '';

  /// The fixed name this store's state is stored under. Together with the
  /// id it must not end with [versionKeySuffix], which is reserved.
  ///
  /// Required: deriving it from `runtimeType` would lose the stored state
  /// whenever the class is renamed or the build is obfuscated. Two store
  /// types must never share a prefix.
  String get storagePrefix;

  /// `storageToken` is used as registration token for hydrated storage.
  /// Uses the optional constructor argument when provided, otherwise [id].
  @nonVirtual
  String get storageToken => '$storagePrefix${_constructorStorageId ?? id}';

  /// Key under which the persisted schema [version] for this store is stored.
  String get _versionToken => versionKeyOf(storageToken);

  /// Whether [toJson] already returns plain JSON: only `null`, `bool`, `num`,
  /// `String`, `List` and `Map<String, ...>` values, nested any way, built
  /// fresh on each call.
  ///
  /// When `true`, the state is written as returned, skipping the traversal
  /// that otherwise converts objects through their `toJson()` and copies the
  /// result. Override it for large states whose [toJson] already does the
  /// full conversion, e.g. with json_serializable's `explicit_to_json: true`
  /// and a generic DTO's `toJson((item) => item.toJson())`.
  ///
  /// Returning a collection the store keeps and mutates breaks change
  /// detection; build new collections in [toJson].
  bool get trustToJson => false;

  /// The current schema version of this store's persisted state.
  ///
  /// Override and increment this whenever the shape produced by [toJson]
  /// (and consumed by [fromJson]) changes in a way that older persisted data
  /// would not satisfy. When a store hydrates data written under a lower
  /// version, [migrate] is invoked to bring it up to date. Defaults to `1`.
  int get version => 1;

  /// Migrates persisted state written under an older schema [version] into the
  /// shape the current [version] expects.
  ///
  /// Invoked during [hydrate] when the stored version is lower than [version],
  /// receiving the [oldVersion] the data was written under and the decoded
  /// [oldState]. Return the upgraded state; it is then passed to [fromJson] and
  /// persisted under the current [version]. When jumping multiple versions,
  /// apply every intermediate step in order with stacked `if (oldVersion < N)`
  /// blocks (Dart `switch` cases do not fall through, so a `switch` would skip
  /// the intermediate upgrades).
  ///
  /// Return `null` to drop the old state instead: it is deleted, [fromJson]
  /// is not called, and the store keeps its initial state.
  ///
  /// The default implementation returns [oldState] unchanged.
  ///
  /// ```dart
  /// @override
  /// int get version => 3;
  ///
  /// @override
  /// Map<String, dynamic>? migrate(int oldVersion, Map<String, dynamic> old) {
  ///   if (oldVersion < 2) return null; // v1 cannot be read any more
  ///   if (oldVersion < 3) {
  ///     old['count'] = old.remove('counter') ?? 0; // renamed field
  ///   }
  ///   return old;
  /// }
  /// ```
  Map<String, dynamic>? migrate(
    int oldVersion,
    Map<String, dynamic> oldState,
  ) =>
      oldState;

  /// Deletes this store's persisted state (and its version key) without
  /// changing its current state.
  ///
  /// Any write pending from before the call is dropped, so the deleted key
  /// cannot be resurrected. Persistence then **stops**; pass `resume: true`
  /// to keep persisting, which writes the current state back as any change
  /// would: right away, or after `persistDelay`.
  /// To stop persisting without deleting anything, use [dispose].
  Future<void> clearPersisted({bool resume = false}) async {
    final target = _boundStorage!;
    _suspend();
    await target.deleteAll([storageToken, _versionToken]);
    if (resume && _selfRef != null) _startPersisting();
  }

  /// Permanently stops this store from persisting state and removes it from
  /// the instance registry. A write that `persistDelay` was holding back is
  /// started first; `await flush()` before [dispose] to wait for it.
  ///
  /// Call this when the store is no longer used. Unlike [clearPersisted], the
  /// stored state is left untouched. Safe to call more than once.
  ///
  /// This releases only the persistence reaction; the store's own MobX
  /// observables and actions remain usable afterwards.
  void dispose() {
    unawaited(flush());
    _stopPersisting();
    final ref = _selfRef;
    if (ref != null) {
      _instances.remove(ref);
      _finalizer.detach(this);
      _selfRef = null;
    }
  }

  /// Responsible for converting the `Map<String, dynamic>` representation
  /// of the store state into a concrete instance of the store state.
  ///
  /// [json] is a fresh, deep copy: every nested map is
  /// `Map<String, dynamic>` and every nested list is `List<dynamic>`, so it
  /// can be handed straight to json_serializable `fromJson` factories.
  void fromJson(Map<String, dynamic> json);

  /// Responsible for converting a concrete instance of the store state
  /// into the the `Map<String, dynamic>` representation.
  ///
  /// If [toJson] returns `null`, then no state changes will be persisted.
  Map<String, dynamic>? toJson();
}

/// {@template hydrated_observer}
/// Handles the failures of every store that was not given its own handler,
/// and hears about migrations. Set [HydratedMobX.observer] to a subclass.
///
/// ```dart
/// class CrashReportingObserver extends HydratedObserver {
///   @override
///   void onStorageError(HydratedMobX store, Object error, StackTrace st) =>
///       crashReporter.record(error, st, reason: store.storageToken);
/// }
/// ```
/// {@endtemplate}
class HydratedObserver {
  /// {@macro hydrated_observer}
  const HydratedObserver();

  /// Called when [store] fails to hydrate. The returned behavior decides
  /// whether its later changes overwrite the stored state. Logs and returns
  /// [HydrationErrorBehavior.overwrite] by default.
  HydrationErrorBehavior onHydrationError(
    HydratedMobX store,
    Object error,
    StackTrace stackTrace,
  ) {
    log(
      'Error hydrating "${store.storageToken}": $error',
      error: error,
      stackTrace: stackTrace,
      name: 'HydratedMobx',
    );
    return HydrationErrorBehavior.overwrite;
  }

  /// Called when [store] fails to serialize or write its state. Persistence
  /// is fire-and-forget, so this is the only place such failures surface.
  /// Logs by default.
  void onStorageError(
    HydratedMobX store,
    Object error,
    StackTrace stackTrace,
  ) {
    log(
      'Error persisting "${store.storageToken}": $error',
      error: error,
      stackTrace: stackTrace,
      name: 'HydratedMobx',
    );
  }

  /// Called after [store]'s [HydratedMobX.migrate] ran from [fromVersion] to
  /// [toVersion]. Does nothing by default.
  void onMigrate(HydratedMobX store, int fromVersion, int toVersion) {}
}

/// Reports that an object could not be serialized due to cyclic references.
/// When the cycle is detected, a [HydratedCyclicError] is thrown.
class HydratedCyclicError extends HydratedUnsupportedError {
  /// The first object that was detected as part of a cycle.
  HydratedCyclicError(super.unsupportedObject);

  @override
  String toString() => 'Cyclic error while state traversing';
}

/// {@template storage_not_found}
/// Exception thrown if there was no [HydratedStorage] specified.
/// This is most likely due to forgetting to setup the [HydratedStorage]:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   HydratedMobX.storage = await HydratedStorage.build(...);
///   runApp(MyApp());
/// }
/// ```
///
/// {@endtemplate}
class StorageNotFound implements Exception {
  /// {@macro storage_not_found}
  const StorageNotFound();

  @override
  String toString() {
    return 'Storage was accessed before it was initialized.\n'
        'Please ensure that storage has been initialized.\n\n'
        'For example:\n\n'
        'HydratedMobX.storage = await HydratedStorage.build(...);';
  }
}

/// Reports that an object could not be serialized.
/// The [unsupportedObject] field holds object that failed to be serialized.
///
/// If an object isn't directly serializable, the serializer calls the `toJson`
/// method on the object. If that call fails, the error will be stored in the
/// [cause] field. If the call returns an object that isn't directly
/// serializable, the [cause] is null.
class HydratedUnsupportedError extends Error {
  /// The object that failed to be serialized.
  /// Error of attempt to serialize through `toJson` method.
  HydratedUnsupportedError(this.unsupportedObject, {this.cause});

  /// The object that could not be serialized.
  final Object? unsupportedObject;

  /// The exception thrown when trying to convert the object.
  final Object? cause;

  @override
  String toString() {
    final safeString = Error.safeToString(unsupportedObject);
    final prefix = cause != null
        ? 'Converting object to an encodable object failed:'
        : 'Converting object did not return an encodable object:';
    return '$prefix $safeString';
  }
}

/// {@template NIL}
/// Type which represents objects that do not support json encoding
///
/// This should never be used and is exposed only for testing purposes.
/// {@endtemplate}
@visibleForTesting
class NIL {
  /// {@macro NIL}
  const NIL();
}

/// Determines how persistence should proceed when hydration fails.
enum HydrationErrorBehavior {
  /// Any newly emitted states will be persisted, which means the previously
  /// cached state will be overwritten. This is the default behavior.
  overwrite,

  /// Any newly emitted states will not be persisted, which means the
  /// previously cached state will be retained.
  retain,
}

/// Signature for a store's own hydration error handler. Returns a
/// [HydrationErrorBehavior] to control how later state changes are persisted.
typedef OnHydrationError = HydrationErrorBehavior Function(
  Object error,
  StackTrace stackTrace,
);

/// Signature for a store's own handler of failed state writes.
typedef OnStorageError = void Function(Object error, StackTrace stackTrace);

/// The failures of a run of token moves: each goes to [_onError], or the
/// first is kept to rethrow once every token has been tried.
class _Failures {
  _Failures(this._onError);

  final void Function(String token, Object error, StackTrace stackTrace)?
      _onError;
  (Object, StackTrace)? _first;

  void add(String token, Object error, StackTrace stackTrace) {
    final onError = _onError;
    if (onError != null) {
      onError(token, error, stackTrace);
    } else {
      _first ??= (error, stackTrace);
    }
  }

  void rethrowFirst() {
    if (_first case (final error, final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
