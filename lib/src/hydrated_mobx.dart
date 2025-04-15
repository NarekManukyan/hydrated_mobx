// ignore_for_file: avoid_catching_errors

import 'dart:async';
import 'dart:developer';

import 'package:hydrated_mobx/src/hydrated_storage.dart';
import 'package:meta/meta.dart';
import 'package:mobx/mobx.dart';

/// {@template hydrated_mobx}
/// An abstract class which enables automatic state persistence for classes using [Store].
/// This allows state to be persisted across hot restarts as well as complete app restarts.
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
  /// Creates a new instance of [HydratedMobX] and automatically hydrates its state.
  ///
  /// The constructor calls [hydrate] which will:
  /// - Attempt to restore the previous state from storage if it exists
  /// - Set up automatic persistence of future state changes
  ///
  /// Example:
  /// ```dart
  /// class CounterStore extends HydratedMobX {
  ///   @observable
  ///   int count = 0;
  ///
  ///   // Constructor will automatically hydrate the state
  ///   CounterStore() : super();
  /// }
  /// ```
  HydratedMobX() {
    hydrate();
  }

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

  late final Storage __storage;

  /// Populates the internal state storage with the latest state.
  /// This should be called in the constructor of the class using the mixin.
  void hydrate({Storage? storage}) {
    __storage = storage ??= HydratedMobX.storage;
    try {
      final stateJson = __storage.read(storageToken) as Map<dynamic, dynamic>?;
      if (stateJson != null) {
        final json = _fromJson(stateJson);
        fromJson(json);
      }
    } catch (error, stackTrace) {
      log(
        'Error hydrating store: $error\n',
        stackTrace: stackTrace,
        name: 'HydratedMobx',
      );
    }

    // Set up reaction to persist state changes
    autorun((_) {
      final json = _toJson(toJson());
      if (json != null) {
        __storage.write(storageToken, json).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          log(
            'Error persisting store: $error\n',
            stackTrace: stackTrace,
            name: 'HydratedMobx',
          );
        });
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
  /// Composed of [storagePrefix] and [id].
  @nonVirtual
  String get storageToken => '$storagePrefix$id';

  /// [clear] is used to wipe or invalidate the cache of a store.
  /// Calling [clear] will delete the cached state of the store
  /// but will not modify the current state of the store.
  Future<void> clear() => __storage.delete(storageToken);

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
  HydratedCyclicError(Object? object) : super(object);

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
