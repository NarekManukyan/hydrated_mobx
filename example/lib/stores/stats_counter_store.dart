import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'stats_counter_store.g.dart';

class StatsCounterStore = StatsCounterStoreBase with _$StatsCounterStore;

/// A counter whose writes the stats page counts, built with or without a
/// `persistDelay`.
abstract class StatsCounterStoreBase extends HydratedMobX with Store {
  StatsCounterStoreBase({
    required String super.storeId,
    required Duration super.persistDelay,
  });

  @observable
  int count = 0;

  @action
  void increment() => count++;

  @override
  String get storagePrefix => 'stats_';

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) {
    count = HydratedJson.readInt(json, 'count');
  }
}
