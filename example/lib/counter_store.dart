import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'counter_store.g.dart';

class CounterStore = CounterStoreBase with _$CounterStore;

abstract class CounterStoreBase extends HydratedMobX with Store {
  @observable
  int count = 0;

  @action
  void increment() => count++;

  @action
  void decrement() {
    count--;
  }

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) {
    count = json['count'] as int;
  }
}
