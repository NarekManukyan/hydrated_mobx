import 'dart:convert' show jsonEncode;

import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

/// Wraps a [Storage] and counts what is written through it, so the demo can
/// show how many writes `persistDelay` and change detection save.
class CountingStorage extends ForwardingStorage {
  CountingStorage(super.inner);

  /// Writes per key since launch (or the last [resetStats]).
  final ObservableMap<String, int> writes = ObservableMap();

  /// Approximate JSON bytes written per key.
  final ObservableMap<String, int> bytes = ObservableMap();

  int get totalWrites => writes.values.fold(0, (a, b) => a + b);

  int writesOf(String key) => writes[key] ?? 0;

  void resetStats() => runInAction(() {
        writes.clear();
        bytes.clear();
      });

  @override
  Future<void> write(String key, dynamic value) async {
    final size = _sizeOf(value);
    await super.write(key, value);
    // Counted once the write has landed, so a reader that rebuilds on these
    // counters reads the new value back.
    runInAction(() {
      writes[key] = (writes[key] ?? 0) + 1;
      bytes[key] = (bytes[key] ?? 0) + size;
    });
  }

  static int _sizeOf(Object? value) {
    try {
      return jsonEncode(value).length;
    } catch (_) {
      return 0;
    }
  }
}
