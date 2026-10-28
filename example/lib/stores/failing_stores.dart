import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'failing_stores.g.dart';

const kBrokenToken = 'broken';

class BrokenStore = BrokenStoreBase with _$BrokenStore;

/// Hydrates from a value that is not a map, so hydration fails.
abstract class BrokenStoreBase extends HydratedMobX with Store {
  BrokenStoreBase();

  @observable
  int count = 0;

  @override
  String get storagePrefix => kBrokenToken;

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) {
    count = HydratedJson.readInt(json, 'count');
  }
}

class UnencodableStore = UnencodableStoreBase with _$UnencodableStore;

/// Holds a value JSON cannot encode, so every write fails.
abstract class UnencodableStoreBase extends HydratedMobX with Store {
  UnencodableStoreBase();

  @observable
  Object payload = Object();

  @override
  String get storagePrefix => 'unencodable';

  @override
  Map<String, dynamic>? toJson() => {'payload': payload};

  @override
  void fromJson(Map<String, dynamic> json) {}
}

class ClosedStorageStore = ClosedStorageStoreBase with _$ClosedStorageStore;

/// Bound to a storage the page closes, so its next write throws
/// `StorageClosedException`.
abstract class ClosedStorageStoreBase extends HydratedMobX with Store {
  ClosedStorageStoreBase(Storage storage) : super(storage: storage);

  @observable
  int count = 0;

  @action
  void increment() => count++;

  @override
  String get storagePrefix => 'closed_demo';

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) {
    count = HydratedJson.readInt(json, 'count');
  }
}
