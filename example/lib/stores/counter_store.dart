import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'counter_store.g.dart';

/// Rapid taps within this window are written to disk once.
const kCounterPersistDelay = Duration(milliseconds: 300);

class CounterStore = CounterStoreBase with _$CounterStore;

/// The basic case: one store, one key, persisted on every change.
abstract class CounterStoreBase extends HydratedMobX with Store {
  CounterStoreBase() : super(persistDelay: kCounterPersistDelay);

  @observable
  int count = 0;

  @action
  void increment() => count++;

  @action
  void decrement() => count--;

  @action
  void reset() => count = 0;

  // Fixed, so renaming the class or obfuscating the build keeps the data.
  @override
  String get storagePrefix => 'counter';

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) {
    count = HydratedJson.readInt(json, 'count');
  }
}
