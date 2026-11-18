import 'package:meta/meta.dart';

/// The writes, deletes and clears a storage has queued, which its `read`
/// and `keys` show already: a store built while one waits for the storage's
/// lock must hydrate the state that is about to be on disk, not the state
/// that is there now.
///
/// Each change is numbered when it is called, so the latest one naming a
/// key decides what a read of it sees.
@internal
class PendingChanges {
  var _calls = 0;

  /// The latest queued write of each key: when it was called, and the value
  /// in the form the storage keeps it.
  final _writes = <String, ({int call, Object? stored})>{};

  /// When each queued delete naming a key was called.
  final _deletes = <String, List<int>>{};

  /// When each queued clear was called. A clear names every key, since a
  /// write queued before it can still add a key the clear then removes.
  final _clears = <int>[];

  /// Whether nothing is queued now.
  bool get isEmpty => _writes.isEmpty && _deletes.isEmpty && _clears.isEmpty;

  /// When the latest queued delete or clear naming [key] was called.
  /// Both lists hold calls in the order they were made, so the last of
  /// each is its latest.
  int? _deletedAt(String key) {
    final deleted = _deletes[key]?.last;
    final cleared = _clears.isEmpty ? null : _clears.last;
    if (deleted == null) return cleared;
    if (cleared == null) return deleted;
    return deleted > cleared ? deleted : cleared;
  }

  /// Whether [key] is to be treated as deleted already.
  bool hides(String key) {
    final deleted = _deletedAt(key);
    if (deleted == null) return false;
    final write = _writes[key];
    return write == null || write.call < deleted;
  }

  /// Whether [key] is to be read as the value of its queued write.
  bool _shows(String key) {
    final write = _writes[key];
    if (write == null) return false;
    final deleted = _deletedAt(key);
    return deleted == null || write.call > deleted;
  }

  /// [key] as a read sees it: the value of its queued write, through
  /// [decode] from the form the storage keeps it; `null` when a queued
  /// delete or clear hides it; or else what [fromStorage] reads.
  Object? read(
    String key, {
    required Object? Function(Object? stored) decode,
    required Object? Function() fromStorage,
  }) {
    if (_shows(key)) return decode(_writes[key]!.stored);
    if (hides(key)) return null;
    return fromStorage();
  }

  /// [stored], the keys the storage holds, as a read sees them: without
  /// those a queued delete or clear hides, and with those only a queued
  /// write adds. [holds] says whether the storage holds a key.
  Iterable<String> keys(
    Iterable<String> stored, {
    required bool Function(String key) holds,
  }) {
    if (isEmpty) return stored;
    return [
      for (final key in stored)
        if (!hides(key)) key,
      for (final key in _writes.keys)
        if (_shows(key) && !holds(key)) key,
    ];
  }

  /// Shows [key] as [stored] from now until [body], the storage's write,
  /// finishes, however it ends: after a failure, reads see what the storage
  /// holds again.
  Future<void> write(String key, Object? stored, Future<void> Function() body) {
    final call = ++_calls;
    _writes[key] = (call: call, stored: stored);
    return Future.sync(body).whenComplete(() {
      if (_writes[key]?.call == call) _writes.remove(key);
    });
  }

  /// Hides [keys] from now until [body], the storage's delete, finishes,
  /// however it ends.
  Future<void> delete(List<String> keys, Future<void> Function() body) {
    final call = ++_calls;
    for (final key in keys) {
      (_deletes[key] ??= []).add(call);
    }
    return Future.sync(body).whenComplete(() {
      for (final key in keys) {
        final calls = _deletes[key]!..remove(call);
        if (calls.isEmpty) _deletes.remove(key);
      }
    });
  }

  /// Hides every key from now until [body], the storage's clear, finishes,
  /// however it ends.
  Future<void> clear(Future<void> Function() body) {
    final call = ++_calls;
    _clears.add(call);
    return Future.sync(body).whenComplete(() => _clears.remove(call));
  }
}
