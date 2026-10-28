import 'package:hydrated_mobx/src/hydrated_mobx.dart';
import 'package:hydrated_mobx/src/hydrated_storage.dart';

/// {@template in_memory_storage}
/// A [Storage] kept in a plain map, for tests and for state that should not
/// outlive the process.
///
/// ```dart
/// setUp(() => HydratedMobX.storage = InMemoryStorage());
/// ```
/// {@endtemplate}
class InMemoryStorage implements Storage {
  /// {@macro in_memory_storage}
  InMemoryStorage([Map<String, dynamic>? initial]) : _data = {...?initial};

  final Map<String, dynamic> _data;
  bool _closed = false;

  void _checkOpen(String operation) {
    if (_closed) throw StorageClosedException(operation);
  }

  @override
  dynamic read(String key) {
    _checkOpen('read');
    return _data[key];
  }

  @override
  Iterable<String> get keys {
    _checkOpen('list keys');
    return _data.keys.toList();
  }

  @override
  Future<void> write(String key, dynamic value) async {
    _checkOpen('write');
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _checkOpen('delete');
    _data.remove(key);
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    _checkOpen('delete');
    keys.toList().forEach(_data.remove);
  }

  @override
  Future<void> clear() async {
    _checkOpen('clear');
    HydratedMobX.suspendAll(storage: this);
    _data.clear();
  }

  @override
  Future<void> close() async {
    _data.clear();
    _closed = true;
  }
}
