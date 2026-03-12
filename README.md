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
- Simple and intuitive API

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  hydrated_mobx: ^1.1.3
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

## Additional information

- For more information about MobX, visit the [MobX documentation](https://mobx.netlify.app/)
- For issues and feature requests, please visit the [GitHub repository](https://github.com/NarekManukyan/hydrated_mobx)
- Contributions are welcome! Feel free to submit pull requests or open issues
