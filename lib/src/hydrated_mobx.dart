// ignore_for_file: avoid_catching_errors

import 'dart:async';
import 'dart:developer';

import 'package:hydrated_mobx/src/hydrated_storage.dart';
import 'package:meta/meta.dart';
import 'package:mobx/mobx.dart';

/// {@template hydrated_mobx}
/// A mixin which enables automatic state persistence for classes using [Store].
/// This allows state to be persisted across hot restarts as well as complete app restarts.
///
/// ```dart
/// class CounterStore with Store, HydratedMobx {
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
/// {@endtemplate}
mixin HydratedMobx {
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
    __storage = storage ??= HydratedMobx.storage;
    try {
      final stateJson = __storage.read(storageToken) as Map<dynamic, dynamic>?;
      if (stateJson != null) {
        final json = Map<String, dynamic>.from(stateJson);
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
      final json = toJson();
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
    });
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
