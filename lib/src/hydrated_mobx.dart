// ignore_for_file: avoid_catching_errors

import 'dart:async';
import 'dart:developer';

import 'package:hydrated_mobx/src/hydrated_storage.dart';
import 'package:meta/meta.dart';
import 'package:mobx/mobx.dart';

/// {@template hydrated_mobx}
/// An abstract class which enables automatic state persistence for classes
/// using [Store]. State can be persisted across hot restarts and app restarts.
///
/// To use HydratedMobX, extend this class and implement the required methods:
/// - [toJson] - Converts the store state to a JSON representation
/// - [fromJson] - Restores the store state from a JSON representation
///
/// Example:
/// ```dart
/// class CounterStore extends HydratedMobX with Store {
///   CounterStore() {
///     hydrate();
///   }
///
///   @observable
///   int count = 0;
///
///   @action
///   void increment() => count++;
///
///   @action
///   void decrement() => count--;
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
/// The store will automatically persist its state whenever it changes.
/// The state will be restored when the store is initialized.
///
/// {@endtemplate}

abstract class HydratedMobX with Store {
  /// Creates a new instance and hydrates its state.
  ///
  /// Optional [storeId]: use for per-instance storage (e.g. per meeting).
  /// Forward with `super(storeId: meetingId)` so the correct key is used.
  ///
  /// Optional [onHydrationError]: invoked when hydration fails. See
  /// [HydrationErrorBehavior] for how the returned value affects persistence.
  ///
  /// Optional [onStorageError]: invoked when persisting a state change fails
  /// (e.g. the disk is full or encryption fails). Defaults to
  /// [defaultOnStorageError], which logs the error.
  HydratedMobX({
    String? storeId,
    OnHydrationError onHydrationError = defaultOnHydrationError,
    OnStorageError onStorageError = defaultOnStorageError,
  }) : _constructorStorageId = storeId {
    hydrate(
      onHydrationError: onHydrationError,
      onStorageError: onStorageError,
    );
  }

  final String? _constructorStorageId;

  late OnStorageError _onStorageError;

  static Storage? _storage;

  /// Setter for instance of [Storage] which will be used to
  /// manage persisting/restoring the store state.
  static set storage(Storage? storage) => _storage = storage;

  /// Instance of [Storage] which will be used to
  /// manage persisting/restoring the store state.
  static Storage get storage {
    if (_storage == null) throw const StorageNotFound();
    return _storage!;
  }

  /// Seeds hydrated [storage] with pre-existing [data] imported from another
  /// persistence layer (e.g. `SharedPreferences`, a legacy Hive box, or a
  /// previous key scheme).
  ///
  /// [data] maps each [storageToken] to the JSON that a store of that token
  /// should hydrate from. Keys therefore follow the same
  /// `'$storagePrefix${storeId ?? id}'` composition used by [storageToken] —
  /// include the `storeId`/`id` component when the target store overrides it.
  ///
  /// [version] is the schema version the imported payloads are already in; it
  /// is recorded so that a store whose [HydratedMobX.version] is higher does
  /// **not** re-run [migrate] against data that is already current. Leave it at
  /// the default (`1`) when importing legacy version-1 data that should be
  /// migrated forward.
  ///
  /// By default, existing keys are left untouched so already-hydrated state is
  /// never clobbered; pass `overwrite: true` to replace them.
  ///
  /// Call this after [storage] has been assigned and before constructing the
  /// stores that should pick the data up:
  ///
  /// ```dart
  /// HydratedMobX.storage = await HydratedStorage.build(...);
  /// await HydratedMobX.importData({
  ///   'CounterStore': {'count': legacyPrefs.getInt('count') ?? 0},
  /// });
  /// final store = CounterStore(); // hydrates from the seeded data
  /// ```
  static Future<void> importData(
    Map<String, Map<String, dynamic>> data, {
    bool overwrite = false,
    int version = 1,
  }) async {
    final store = HydratedMobX.storage;
    for (final entry in data.entries) {
      if (!overwrite && store.read(entry.key) != null) continue;
      await store.write(entry.key, entry.value);
      if (version > 1) {
        await store.write('${entry.key}$_versionKeySuffix', version);
      }
    }
  }

  late Storage __storage;

  /// Registry of live instances so [Storage]-level clears can reach every
  /// store's persistence reaction before the underlying box is wiped.
  ///
  /// Entries are [WeakReference]s so the registry never keeps a store alive on
  /// its own: while a store is persisting it is kept reachable by its active
  /// MobX reaction, but once that reaction is disposed (via [clear], [dispose],
  /// or [disposeAllForClear]) the store becomes eligible for garbage collection
  /// and [_finalizer] prunes its (now-dead) entry automatically.
  static final Set<WeakReference<HydratedMobX>> _instances =
      <WeakReference<HydratedMobX>>{};

  /// Prunes a store's registry entry once the store has been collected.
  static final Finalizer<WeakReference<HydratedMobX>> _finalizer =
      Finalizer<WeakReference<HydratedMobX>>(_instances.remove);

  WeakReference<HydratedMobX>? _selfRef;
  ReactionDisposer? _persistDisposer;
  int _clearGeneration = 0;
  HydrationErrorBehavior _behavior = HydrationErrorBehavior.overwrite;

  /// The schema [version] currently recorded on disk for this store, tracked so
  /// the version key is stamped once (after the state write) rather than on
  /// every state change. `null` means no version has been recorded yet.
  int? _lastStampedVersion;

  /// Suffix appended to a [storageToken] to form the key under which the
  /// persisted schema [version] is stored.
  static const _versionKeySuffix = '.__version';

  /// Registers this instance in [_instances] exactly once.
  void _register() {
    if (_selfRef != null) return;
    final ref = _selfRef = WeakReference<HydratedMobX>(this);
    _instances.add(ref);
    _finalizer.attach(this, ref, detach: this);
  }

  /// Disposes the persistence reactions of every live [HydratedMobX] instance
  /// and bumps their clear generation so any in-flight write scheduled by an
  /// autorun is dropped instead of resurrecting cleared state. Dead registry
  /// entries are pruned along the way.
  ///
  /// Intended to be called by [Storage] implementations from inside their
  /// `clear()` before wiping the backing store.
  @internal
  static void disposeAllForClear() {
    _instances.removeWhere((ref) {
      final instance = ref.target;
      if (instance == null) return true;
      instance._clearGeneration++;
      instance._persistDisposer?.call();
      instance._persistDisposer = null;
      return false;
    });
  }

  /// Populates the internal state storage with the latest state.
  /// This should be called in the constructor of the class using the mixin.
  ///
  /// [onHydrationError] is invoked when hydration fails. The returned
  /// [HydrationErrorBehavior] determines whether subsequent state changes
  /// overwrite the cached state ([HydrationErrorBehavior.overwrite], default)
  /// or retain it ([HydrationErrorBehavior.retain]) — in which case no writes
  /// are persisted from this instance until a future successful [hydrate].
  void hydrate({
    Storage? storage,
    OnHydrationError onHydrationError = defaultOnHydrationError,
    OnStorageError onStorageError = defaultOnStorageError,
  }) {
    __storage = storage ??= HydratedMobX.storage;
    _onStorageError = onStorageError;
    _register();
    _behavior = HydrationErrorBehavior.overwrite;
    // The version already recorded on disk (null/non-int means unversioned).
    // The persistence reaction stamps [version] only after the state that
    // produced it has been written, so the version can never lead the state.
    final rawVersion = __storage.read(_versionToken);
    if (rawVersion != null && rawVersion is! int) {
      log(
        'Persisted version for "$storageToken" is not an int ($rawVersion); '
        'treating the data as unversioned.',
        name: 'HydratedMobx',
      );
    }
    _lastStampedVersion = _cast<int>(rawVersion);
    try {
      final stateJson = __storage.read(storageToken) as Map<dynamic, dynamic>?;
      if (stateJson != null) {
        var json = _fromJson(stateJson);
        // Data written before schema versioning existed has no version key and
        // is treated as version 1.
        final storedVersion = _lastStampedVersion ?? 1;
        if (storedVersion < version) {
          json = migrate(storedVersion, json);
        } else if (storedVersion > version) {
          log(
            'Persisted schema version $storedVersion for "$storageToken" is '
            'newer than the current version $version; loading without '
            'migration. Data may not match the current schema.',
            name: 'HydratedMobx',
          );
        }
        fromJson(json);
      }
    } catch (error, stackTrace) {
      log(
        'Error hydrating store: $error\n',
        stackTrace: stackTrace,
        name: 'HydratedMobx',
      );
      _behavior = onHydrationError(error, stackTrace);
    }

    _startPersisting();
  }

  /// Arms the MobX reaction that persists state changes.
  ///
  /// Disposes any reaction from a previous call first, so re-invoking
  /// [hydrate] (or re-arming after a [clear]) never leaks a reaction or writes
  /// twice. Each reaction captures the clear generation active when it was
  /// armed, so a write scheduled before a [clear] is dropped rather than
  /// resurrecting cleared state.
  void _startPersisting() {
    _persistDisposer?.call();
    final myGeneration = _clearGeneration;
    _persistDisposer = autorun((_) {
      if (myGeneration != _clearGeneration) return;
      if (_behavior == HydrationErrorBehavior.retain) return;
      final json = _toJson(toJson());
      if (json == null) return;
      final stateWrite = __storage.write(storageToken, json);
      // Only versioned stores (version > 1) record a version key; a default
      // v1 store needs none (an absent key reads back as version 1).
      if (version > 1 && _lastStampedVersion != version) {
        // Stamp the schema version only after the state write succeeds, so a
        // failure or crash leaves the version behind the state (which just
        // re-runs migration next launch) rather than ahead of it (which would
        // skip a required migration and corrupt data).
        stateWrite.then((_) {
          _lastStampedVersion = version;
          return __storage.write(_versionToken, version);
        }).catchError(_onStorageError);
      } else {
        stateWrite.catchError(_onStorageError);
      }
    });
  }

  Map<String, dynamic>? _toJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return _cast<Map<String, dynamic>>(_traverseWrite(json).value);
  }

  Map<String, dynamic> _fromJson(dynamic json) {
    final dynamic traversedJson = _traverseRead(json);
    final castJson = _cast<Map<String, dynamic>>(traversedJson);
    return castJson ?? <String, dynamic>{};
  }

  dynamic _traverseRead(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>((dynamic key, dynamic value) {
        return MapEntry<String, dynamic>(
          _cast<String>(key) ?? '',
          _traverseRead(value),
        );
      });
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        value[i] = _traverseRead(value[i]);
      }
    }
    return value;
  }

  T? _cast<T>(dynamic x) => x is T ? x : null;

  _Traversed _traverseWrite(Object? value) {
    final dynamic traversedAtomicJson = _traverseAtomicJson(value);
    if (traversedAtomicJson is! NIL) {
      return _Traversed.atomic(traversedAtomicJson);
    }
    final dynamic traversedComplexJson = _traverseComplexJson(value);
    if (traversedComplexJson is! NIL) {
      return _Traversed.complex(traversedComplexJson);
    }
    try {
      _checkCycle(value);
      final dynamic customJson = _toEncodable(value);
      final dynamic traversedCustomJson = _traverseJson(customJson);
      if (traversedCustomJson is NIL) {
        throw HydratedUnsupportedError(value);
      }
      _removeSeen(value);
      return _Traversed.complex(traversedCustomJson);
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
      if (object.isEmpty) return object;
      _checkCycle(object);
      List<dynamic>? list;
      for (var i = 0; i < object.length; i++) {
        final traversed = _traverseWrite(object[i]);
        list ??= traversed.outcome == _Outcome.atomic
            ? object.sublist(0)
            : (<dynamic>[]..length = object.length);
        list[i] = traversed.value;
      }
      _removeSeen(object);
      return list;
    } else if (object is Map) {
      _checkCycle(object);
      final map = <String, dynamic>{};
      object.forEach((dynamic key, dynamic value) {
        final castKey = _cast<String>(key);
        if (castKey != null) {
          map[castKey] = _traverseWrite(value).value;
        }
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

  /// [id] is used to uniquely identify multiple instances
  /// of the same store type.
  /// In most cases it is not necessary;
  /// however, if you wish to intentionally have multiple instances
  /// of the same store, then you must override [id]
  /// and return a unique identifier for each store instance
  /// in order to keep the caches independent of each other.
  String get id => '';

  /// Storage prefix which can be overridden to provide a custom
  /// storage namespace.
  /// Defaults to [runtimeType] but should be overridden in cases
  /// where stored data should be resilient to obfuscation or persist
  /// between debug/release builds.
  String get storagePrefix => runtimeType.toString();

  /// `storageToken` is used as registration token for hydrated storage.
  /// Uses the optional constructor argument when provided, otherwise [id].
  @nonVirtual
  String get storageToken => '$storagePrefix${_constructorStorageId ?? id}';

  /// Key under which the persisted schema [version] for this store is stored.
  @nonVirtual
  String get _versionToken => '$storageToken$_versionKeySuffix';

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
  /// The default implementation returns [oldState] unchanged.
  ///
  /// ```dart
  /// @override
  /// int get version => 2;
  ///
  /// @override
  /// Map<String, dynamic> migrate(int oldVersion, Map<String, dynamic> old) {
  ///   if (oldVersion < 2) {
  ///     old['count'] = old.remove('counter') ?? 0; // renamed field
  ///   }
  ///   return old;
  /// }
  /// ```
  Map<String, dynamic> migrate(
    int oldVersion,
    Map<String, dynamic> oldState,
  ) =>
      oldState;

  /// [clear] is used to wipe or invalidate the cache of a store.
  /// Calling [clear] will delete the cached state of the store
  /// but will not modify the current state of the store.
  ///
  /// Any in-flight write scheduled before the clear is dropped, so the deleted
  /// key cannot be resurrected.
  ///
  /// By default persistence then **stops**: future observable changes are no
  /// longer written. Pass `resume: true` to keep persisting after the wipe —
  /// subsequent changes are saved again (unless hydration failed with
  /// [HydrationErrorBehavior.retain]). To stop persisting permanently, use
  /// [dispose].
  Future<void> clear({bool resume = false}) async {
    _clearGeneration++;
    _persistDisposer?.call();
    _persistDisposer = null;
    await __storage.delete(storageToken);
    // Delete the paired version key so a later re-seed/import is not skipped by
    // stale version metadata, and so resumed writes re-stamp the version.
    await __storage.delete(_versionToken);
    _lastStampedVersion = null;
    if (resume) _startPersisting();
  }

  /// Permanently stops this store from persisting state and removes it from the
  /// internal instance registry.
  ///
  /// Call this when the store is no longer used (e.g. from the owning widget's
  /// `dispose`) to release the persistence reaction and let the instance be
  /// garbage collected. Unlike [clear], the cached state on disk is left
  /// untouched and persistence does not resume. Safe to call more than once.
  ///
  /// Deterministically removes the instance from the registry. Stores that are
  /// simply dropped without calling [dispose] are still pruned lazily once the
  /// garbage collector reclaims them, but calling [dispose] is preferred: it
  /// releases the reaction immediately rather than waiting for collection.
  ///
  /// This releases only the persistence reaction; it does not tear down the
  /// store's own MobX observables/actions, which remain usable afterwards.
  void dispose() {
    _persistDisposer?.call();
    _persistDisposer = null;
    final ref = _selfRef;
    if (ref != null) {
      _instances.remove(ref);
      _finalizer.detach(this);
      _selfRef = null;
    }
  }

  /// Responsible for converting the `Map<String, dynamic>` representation
  /// of the store state into a concrete instance of the store state.
  void fromJson(Map<String, dynamic> json);

  /// Responsible for converting a concrete instance of the store state
  /// into the the `Map<String, dynamic>` representation.
  ///
  /// If [toJson] returns `null`, then no state changes will be persisted.
  Map<String, dynamic>? toJson();
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
///   HydratedMobx.storage = await HydratedStorage.build();
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
        'HydratedMobx.storage = await HydratedStorage.build();';
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
  HydratedUnsupportedError(
    this.unsupportedObject, {
    this.cause,
  });

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

/// Signature for a callback invoked when hydration fails. Returns a
/// [HydrationErrorBehavior] to control how subsequent state changes are
/// persisted.
typedef OnHydrationError = HydrationErrorBehavior Function(
  Object error,
  StackTrace stackTrace,
);

/// Default [OnHydrationError] handler. Returns
/// [HydrationErrorBehavior.overwrite].
HydrationErrorBehavior defaultOnHydrationError(
  Object error,
  StackTrace stackTrace,
) =>
    HydrationErrorBehavior.overwrite;

/// Signature for a callback invoked when persisting a state change fails.
///
/// Persistence is fire-and-forget, so a failing write never interrupts the
/// store; this callback is the only way to observe such failures (e.g. to
/// report them to a crash reporter).
typedef OnStorageError = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Default [OnStorageError] handler. Logs the error via `dart:developer`.
void defaultOnStorageError(Object error, StackTrace stackTrace) {
  log(
    'Error persisting store: $error\n',
    stackTrace: stackTrace,
    name: 'HydratedMobx',
  );
}

enum _Outcome { atomic, complex }

class _Traversed {
  _Traversed._({required this.outcome, required this.value});
  _Traversed.atomic(dynamic value)
      : this._(outcome: _Outcome.atomic, value: value);
  _Traversed.complex(dynamic value)
      : this._(outcome: _Outcome.complex, value: value);
  final _Outcome outcome;
  final dynamic value;
}
