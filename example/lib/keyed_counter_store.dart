import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'keyed_counter_store.g.dart';

/// Example of a store that can use a per-instance storage key via optional
/// [storeId]. Use KeyedCounterStore() or KeyedCounterStore(storeId: 'demo').
class KeyedCounterStore = KeyedCounterStoreBase with _$KeyedCounterStore;

abstract class KeyedCounterStoreBase extends HydratedMobX with Store {
  KeyedCounterStoreBase({String? storeId}) : super(storeId: storeId);

  @observable
  int count = 0;

  @action
  void increment() => count++;

  @action
  void decrement() => count--;

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) {
    count = HydratedJson.readInt(json, 'count', defaultValue: 0);
  }
}
