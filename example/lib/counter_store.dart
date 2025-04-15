import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'counter_store.g.dart';

class CounterStore = _CounterStoreBase with _$CounterStore;

abstract class _CounterStoreBase extends HydratedMobX {
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
