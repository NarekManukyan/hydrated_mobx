<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

# HydratedMobX

A Flutter package that automatically persists and restores MobX stores. Built to work with Flutter's state management solution MobX.

> This package uses some code from [hydrated_bloc](https://pub.dev/packages/hydrated_bloc) by Felix Angelov, which is licensed under the MIT License. We extend our gratitude to the original authors for their work.

## Features

- Automatically persists and restores MobX stores
- Supports encryption for secure storage
- Works on all platforms (iOS, Android, Web, Linux, macOS, Windows)
- Built on top of Hive for fast and efficient storage
- Schema versioning with a `migrate` hook for evolving persisted state
- Import existing data from another persistence layer via `importData`
- Simple and intuitive API

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  hydrated_mobx: ^1.2.0
```

## Usage

1. Initialize HydratedMobX in your main.dart:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  HydratedMobX.storage = await HydratedStorage.build(
    storageDirectory: HydratedStorageDirectory(appDocumentDir.path),
  );
  runApp(App());
}
```

2. Create a hydrated store:

```dart
import 'package:mobx/mobx.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

part 'counter_store.g.dart';

class CounterStore = _CounterStore with _$CounterStore;

abstract class _CounterStore extends HydratedMobX with Store {
  @observable
  int count = 0;

  @action
  void increment() => count++;

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) {
    count = json['count'] as int;
  }
}
```

### Overriding the storage key (per-instance id)

When you have multiple instances of the same store (e.g. one per meeting or per user), pass the id to `super(storeId: ...)` so hydration uses the correct key. This works with dependency injection (e.g. injectable):

```dart
abstract class _MeetingStoreBase extends HydratedMobX with Store {
  _MeetingStoreBase(
    DioService dioService,
    MeetingsStore meetingsStore,
    @factoryParam String meetingId,
  ) : _meetingId = meetingId,
      super(storeId: meetingId);

  final String _meetingId;

  @override
  String get id => _meetingId;
  // ...
}
```

See the example app’s `KeyedCounterStore` for a minimal example.

### Type-safe fromJson / toJson with HydratedJson

To avoid manual type checks and try/catch in `fromJson`/`toJson`, use the `HydratedJson` helpers:

```dart
import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

@override
void fromJson(Map<String, dynamic> json) {
  _meetings = HydratedJson.readList(
    json,
    'meetings',
    MeetingDto.fromJson,
  ).asObservable();
  _meta = HydratedJson.readObject(json, 'meta', MetaDto.fromJson) ??
      MetaDto(take: 20);
}

@override
Map<String, dynamic> toJson() => {
  'meetings': HydratedJson.writeList(_meetings, (e) => e.toJson()),
  'meta': _meta.toJson(),
};
```

Available helpers: `readList`, `readObject`, `readString`, `readInt`, `readDouble`, `readBool`, `writeList`. They return safe defaults (e.g. empty list, 0, null) when the key is missing or the value has the wrong type.

### Migrating persisted state across schema changes

When the shape of your persisted state changes between app releases, bump
`version` and implement `migrate` to upgrade older data. `migrate` is called
during hydration whenever the stored version is lower than the current one; its
result is passed to `fromJson` and re-persisted under the new version, so it runs
only once per upgrade. Data written before versioning existed is treated as
version `1`.

```dart
class CounterStore extends HydratedMobX with Store {
  CounterStore() { hydrate(); }

  final Observable<int> _count = Observable(0);
  int get count => _count.value;

  @override
  int get version => 2;

  @override
  Map<String, dynamic> migrate(int oldVersion, Map<String, dynamic> old) {
    if (oldVersion < 2) {
      // v1 stored the value under 'counter'; v2 renamed it to 'count'.
      old['count'] = old.remove('counter') ?? 0;
    }
    return old;
  }

  @override
  Map<String, dynamic>? toJson() => {'count': _count.value};

  @override
  void fromJson(Map<String, dynamic> json) =>
      _count.value = (json['count'] as int?) ?? 0;
}
```

When jumping multiple versions at once, handle every intermediate step inside
`migrate` (for example a `switch` with fall-through on `oldVersion`).

### Importing existing data

To bring data in from another persistence layer — `SharedPreferences`, a legacy
Hive box, or a previous key scheme — seed the storage with
`HydratedMobX.importData` after storage is set and before you construct the
stores that should pick it up. Keys map to each store's `storageToken`
(`'$storagePrefix$id'`). Existing keys are left untouched by default; pass
`overwrite: true` to replace them.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HydratedMobX.storage = await HydratedStorage.build(
    storageDirectory: HydratedStorageDirectory(
      (await getTemporaryDirectory()).path,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  await HydratedMobX.importData({
    'CounterStore': {'count': prefs.getInt('count') ?? 0},
  });

  final store = CounterStore(); // hydrates from the imported data
  runApp(App());
}
```

### Observing persistence failures

State is persisted in the background (fire-and-forget), so a failing write never
interrupts your store. To observe such failures — a full disk, an encryption
error — pass an `onStorageError` handler. It defaults to logging the error.

```dart
class CounterStore extends HydratedMobX with Store {
  CounterStore()
      : super(
          onStorageError: (error, stackTrace) {
            FirebaseCrashlytics.instance.recordError(error, stackTrace);
          },
        ) {
    hydrate();
  }
  // ...
}
```

> **Note on multiple instances:** the default storage key is derived from the
> store's `runtimeType`, so two live instances of the same store type share one
> key and overwrite each other. If you intentionally keep several instances of
> the same type, override `id` (or pass `storeId`) to give each a distinct key.

### Clearing, resuming, and disposing

- `clear()` deletes the store's cached state and, by default, **stops**
  persisting further changes.
- `clear(resume: true)` deletes the cached state but keeps persisting, so
  subsequent changes are saved again.
- `dispose()` permanently stops persistence and removes the store from the
  internal registry so it can be garbage collected. Call it when the store is
  no longer used (e.g. from the owning widget's `dispose`); the on-disk state is
  left untouched.

```dart
await store.clear();              // wipe cache, stop persisting
await store.clear(resume: true);  // wipe cache, keep persisting
store.dispose();                  // stop persisting for good, keep stored data
```

**Call `dispose()` when a store is scoped to a widget.** A persisting store is
kept alive by its internal MobX reaction (this is how it observes changes), so a
store you simply drop is not garbage-collected until that reaction is released.
Calling `dispose()` releases it immediately. For a store owned by a `State`,
dispose it from the widget's `dispose`:

```dart
class _MyPageState extends State<MyPage> {
  final store = CounterStore();

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  // ...
}
```

Long-lived, app-wide singleton stores don't need this — they live for the
whole session by design.

## Additional information

- For more information about MobX, visit the [MobX documentation](https://mobx.netlify.app/)
- For issues and feature requests, please visit the [GitHub repository](https://github.com/NarekManukyan/hydrated_mobx)
- Contributions are welcome! Feel free to submit pull requests or open issues
