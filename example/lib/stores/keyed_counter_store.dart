import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'keyed_counter_store.g.dart';

class KeyedCounterStore = KeyedCounterStoreBase with _$KeyedCounterStore;

/// Many instances of one store type: each `storeId` gets its own key,
/// `keyed_counter_<id>`.
abstract class KeyedCounterStoreBase extends HydratedMobX with Store {
  KeyedCounterStoreBase(String storeId) : super(storeId: storeId);

  @observable
  int count = 0;

  @action
  void increment() => count++;

  @action
  void decrement() => count--;

  @override
  String get storagePrefix => 'keyed_counter_';

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) {
    count = HydratedJson.readInt(json, 'count');
  }
}
