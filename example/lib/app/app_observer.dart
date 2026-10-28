import 'dart:async';

import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

enum LogKind { hydrationError, storageError, migration }

class LogEntry {
  LogEntry(this.kind, this.token, this.message) : at = DateTime.now();

  final LogKind kind;
  final String token;
  final String message;
  final DateTime at;
}

/// Set once as [HydratedMobX.observer]: every store without its own handler
/// reports here, so the app needs no per-store error callbacks.
class AppObserver extends HydratedObserver {
  final ObservableList<LogEntry> log = ObservableList();

  void clearLog() => runInAction(log.clear);

  // Callbacks can arrive while a widget builds (a store hydrating in its
  // constructor); adding to the observed log then would rebuild mid-build,
  // so it is added a microtask later.
  void _add(LogKind kind, HydratedMobX store, String message) =>
      scheduleMicrotask(
        () => runInAction(
          () => log.insert(0, LogEntry(kind, store.storageToken, message)),
        ),
      );

  @override
  HydrationErrorBehavior onHydrationError(
    HydratedMobX store,
    Object error,
    StackTrace stackTrace,
  ) {
    _add(LogKind.hydrationError, store, '$error');
    // Keep the unreadable value on disk instead of overwriting it, so it
    // can still be inspected (and recovered) later.
    return HydrationErrorBehavior.retain;
  }

  @override
  void onStorageError(
    HydratedMobX store,
    Object error,
    StackTrace stackTrace,
  ) =>
      _add(LogKind.storageError, store, '$error');

  @override
  void onMigrate(HydratedMobX store, int fromVersion, int toVersion) =>
      _add(LogKind.migration, store, 'v$fromVersion → v$toVersion');
}

/// Set as [HydratedMobX.observer] in `main`.
final appObserver = AppObserver();
