import 'package:hydrated_mobx/hydrated_mobx.dart';

/// Lets pending autoruns and storage writes (including Hive's lock) finish.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// An [InMemoryStorage] that records the key of every write, and can be told
/// to fail them.
class RecordingStorage extends InMemoryStorage {
  final writes = <String>[];
  bool failWrites = false;

  @override
  Future<void> write(String key, dynamic value) {
    writes.add(key);
    if (failWrites) return Future.error(Exception('write failed'));
    return super.write(key, value);
  }
}
