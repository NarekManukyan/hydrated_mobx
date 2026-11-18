import 'package:meta/meta.dart';

/// The keys a storage has queued deletes for, which its `read` and `keys`
/// treat as gone already: a store built while a delete waits for the
/// storage's lock must not hydrate a value that is about to disappear.
@internal
class PendingDeletes {
  /// How many queued deletes name each key.
  final _counts = <String, int>{};

  /// Queued clears. While one is pending every key is hidden, since a write
  /// queued before it can still add a key the clear then removes.
  var _clears = 0;

  /// Whether nothing is hidden now.
  bool get isEmpty => _clears == 0 && _counts.isEmpty;

  /// Whether [key] is to be treated as deleted already.
  bool hides(String key) => _clears > 0 || _counts.containsKey(key);

  /// Hides [keys] from now until [delete] finishes, however it ends.
  Future<void> delete(List<String> keys, Future<void> Function() delete) {
    for (final key in keys) {
      _counts.update(key, (n) => n + 1, ifAbsent: () => 1);
    }
    return Future.sync(delete).whenComplete(() {
      for (final key in keys) {
        if (_counts.update(key, (n) => n - 1) == 0) _counts.remove(key);
      }
    });
  }

  /// Hides every key from now until [clear] finishes, however it ends.
  Future<void> clear(Future<void> Function() clear) {
    _clears++;
    return Future.sync(clear).whenComplete(() => _clears--);
  }
}
