# HydratedMobX example

A Flutter app with one screen per `hydrated_mobx` feature area:

| Screen | Shows |
| --- | --- |
| Counter | A store that survives a restart; `persistDelay` and `flush()` |
| Keyed instances | One store type, one key per `storeId` |
| Write stats | Writes counted through a `ForwardingStorage`: 100 changes, 1 write |
| Namespaces | Session and account boxes; sign-out clears one; `clearAll(where:)` |
| Schema migration | Seeding old data with `importData`; `migrate` upgrading or dropping it |
| Eviction | A per-item cache bounded by `maxEntries` and `evictable` |
| Observer & errors | Hydration, serialization and closed-storage errors in one log |
| Storage inspector | Every key in every storage, with delete and clear |
| Encryption | An AES-256 box; the note is not in the file as plain text |
| trustToJson | Time per write of a 2000-row state, with and without it |
| Large state | Notes kept gzipped in a box, moved to a `FileStorage` with `transferTokens`, opened with `preload` |

`moveTokens` and `LegacyTokens` are meant to run once, at app startup, before
any store exists. The example app has no 1.x keys to move, so it does not call
them; `test/move_tokens_test.dart` shows them at work.

## Run it

```sh
cd example
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

## A minimal store

```dart
part 'counter_store.g.dart';

class CounterStore = CounterStoreBase with _$CounterStore;

abstract class CounterStoreBase extends HydratedMobX with Store {
  @observable
  int count = 0;

  @action
  void increment() => count++;

  // Required: the storage key this store's state is saved under.
  @override
  String get storagePrefix => 'counter';

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) =>
      count = json['count'] as int? ?? 0;
}
```

Build the storage once in `main`, before the first store is created:

```dart
HydratedMobX.storage = await HydratedStorage.build(
  storageDirectory: HydratedStorageDirectory(
    (await getApplicationSupportDirectory()).path,
  ),
);
```

See the [package README](../README.md) for the full API.
