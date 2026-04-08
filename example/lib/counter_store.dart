import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'counter_store.g.dart';

class CounterStore = CounterStoreBase with _$CounterStore;

abstract class CounterStoreBase extends HydratedMobX with Store {
  CounterStoreBase()
      : super(
          onHydrationError: (error, stackTrace) {
            // Log/report the error here. Returning `retain` keeps the
            // previously cached state and skips persisting new writes until
            // the next successful hydration; `overwrite` (default) lets new
            // state replace the corrupted cache.
            // ignore: avoid_print
            print('CounterStore hydration failed: $error');
            return HydrationErrorBehavior.overwrite;
          },
        );

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
