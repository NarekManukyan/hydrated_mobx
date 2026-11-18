import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hydrated_mobx/src/hydrated_encoding.dart';
import 'package:hydrated_mobx/src/hydrated_mobx.dart';
import 'package:hydrated_mobx/src/hydrated_storage.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';

/// {@template file_storage}
/// A [Storage] that keeps each key in its own file and nothing in memory
/// until it is read, for per-id state (one store per document, chat or
/// note) that should cost no RAM while its store does not exist.
///
/// A `HydratedStorage` box holds every value in memory for as long as it is
/// open, so its memory grows with what is on disk. Here, opening reads only
/// the directory listing, and memory holds the values that were read or
/// written lately, up to `cacheBytes`.
///
/// [read] stays synchronous, as stores need: a value that is not cached is
/// read from its file right there, which blocks for as long as the read
/// takes. Call [preload] first on paths where that matters, e.g. while
/// navigating to the screen that creates the store:
///
/// ```dart
/// final notes = await FileStorage.build(directory: '$support/notes');
///
/// await notes.preload('note_$id');
/// final store = NoteStore(id, storage: notes); // hydrates from the cache
/// ```
///
/// A write goes to a temporary file that is then renamed over the old one,
/// so a crash leaves the old value or the new one, never a torn file.
/// Values are JSON (or bytes), as [HydratedEncoding.json] or
/// [HydratedEncoding.gzipJson]. Only one instance may use a directory at a
/// time. Not available on the web.
/// {@endtemplate}
class FileStorage implements UseTrackingStorage {
  FileStorage._(
    this._directory,
    this._keys, {
    required HydratedEncoding encoding,
    required int cacheBytes,
    required Duration useResolution,
    required DateTime Function() clock,
  })  : _encoding = encoding,
        _cacheLimit = cacheBytes,
        _useResolution = useResolution,
        _clock = clock;

  /// The `cacheBytes` used when none is given to [build].
  static const defaultCacheBytes = 8 << 20;

  /// Extension of the file that holds a key.
  static const _extension = '.hyd';

  /// Extension of a value being written, before it is renamed into place.
  static const _tempExtension = '.tmp';

  /// The longest file name most file systems accept is 255 bytes.
  static const _maxNameLength = 255;

  /// Opens the storage kept in [directory], creating it if needed.
  ///
  /// - [encoding] is how values are written: [HydratedEncoding.gzipJson]
  ///   (the default, smallest) or [HydratedEncoding.json]. Files written
  ///   either way read back whatever the setting.
  /// - [cacheBytes] bounds the encoded bytes kept in memory, most recently
  ///   used first. A value larger than that is never cached.
  /// - [maxAge], [maxEntries] and [evictable] evict as with
  ///   `HydratedStorage.build`, when the storage opens: see [evict].
  /// - [useResolution]: how often [markUsed] rewrites a file's use time at
  ///   most.
  static Future<FileStorage> build({
    required String directory,
    HydratedEncoding encoding = HydratedEncoding.gzipJson,
    int cacheBytes = defaultCacheBytes,
    Duration? maxAge,
    int? maxEntries,
    bool Function(String key)? evictable,
    Duration useResolution = HydratedStorage.defaultUseResolution,
    @visibleForTesting DateTime Function() clock = DateTime.now,
  }) async {
    if (encoding == HydratedEncoding.tree) {
      throw ArgumentError.value(
        encoding,
        'encoding',
        'must be json or gzipJson; files hold bytes',
      );
    }
    if (cacheBytes < 0) {
      throw ArgumentError.value(cacheBytes, 'cacheBytes', 'must be >= 0');
    }
    if (maxAge != null && maxAge.isNegative) {
      throw ArgumentError.value(maxAge, 'maxAge', 'must not be negative');
    }
    final dir = Directory(directory);
    await dir.create(recursive: true);
    final keys = <String>{};
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (name.endsWith(_tempExtension)) {
        // A write the process did not finish; the old value is intact.
        await entry.delete();
      } else if (_keyOf(name) case final key?) {
        keys.add(key);
      }
    }
    final storage = FileStorage._(
      dir,
      keys,
      encoding: encoding,
      cacheBytes: cacheBytes,
      useResolution: useResolution,
      clock: clock,
    );
    if (maxAge != null || maxEntries != null) {
      await storage.evict(
        olderThan: maxAge,
        maxEntries: maxEntries,
        where: evictable,
      );
    }
    return storage;
  }

  final Directory _directory;
  final HydratedEncoding _encoding;
  final int _cacheLimit;
  final Duration _useResolution;
  final DateTime Function() _clock;

  /// Every key with a file, so reads of absent keys cost no I/O.
  final Set<String> _keys;

  /// Encoded bytes of recently used keys, least recently used first.
  final _cache = <String, Uint8List>{};
  int _cachedBytes = 0;

  /// Use times (ms since epoch) known without asking the file system.
  final _usedAt = <String, int>{};

  final _lock = Lock();
  bool _closed = false;

  static String _nameOf(String key) {
    final name =
        '${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}$_extension';
    if (name.length > _maxNameLength) {
      throw ArgumentError.value(key, 'key', 'is too long for a file name');
    }
    return name;
  }

  static String? _keyOf(String name) {
    if (!name.endsWith(_extension)) return null;
    final encoded = name.substring(0, name.length - _extension.length);
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    } on FormatException {
      return null; // Not a file this storage wrote.
    }
  }

  File _fileOf(String key) =>
      File('${_directory.path}${Platform.pathSeparator}${_nameOf(key)}');

  void _checkOpen(String operation) {
    if (_closed) throw StorageClosedException(operation);
  }

  Future<T> _locked<T>(String operation, Future<T> Function() body) {
    _checkOpen(operation);
    return _lock.synchronized(() {
      _checkOpen(operation);
      return body();
    });
  }

  void _cachePut(String key, Uint8List bytes) {
    _cacheRemove(key);
    if (bytes.length > _cacheLimit) return;
    _cache[key] = bytes;
    _cachedBytes += bytes.length;
    while (_cachedBytes > _cacheLimit) {
      _cacheRemove(_cache.keys.first);
    }
  }

  void _cacheRemove(String key) {
    final bytes = _cache.remove(key);
    if (bytes != null) _cachedBytes -= bytes.length;
  }

  /// The encoded bytes held in memory now.
  @visibleForTesting
  int get cachedBytes => _cachedBytes;

  /// Reads [key] (and its version key) into memory, so that a store
  /// constructed next hydrates without touching the disk.
  Future<void> preload(String key) => _locked('preload', () async {
        for (final k in [key, HydratedMobX.versionKeyOf(key)]) {
          if (!_keys.contains(k) || _cache.containsKey(k)) continue;
          try {
            _cachePut(k, await _fileOf(k).readAsBytes());
          } on PathNotFoundException {
            _keys.remove(k); // Deleted behind this storage's back.
          }
        }
      });

  @override
  dynamic read(String key) {
    _checkOpen('read');
    if (!_keys.contains(key)) return null;
    var bytes = _cache.remove(key);
    if (bytes != null) {
      _cache[key] = bytes; // Most recently used now.
    } else {
      try {
        bytes = _fileOf(key).readAsBytesSync();
      } on PathNotFoundException {
        _keys.remove(key);
        return null;
      }
      _cachePut(key, bytes);
    }
    return _FileCodec.decode(bytes);
  }

  @override
  Iterable<String> get keys {
    _checkOpen('list keys');
    return _keys.toList();
  }

  @override
  Future<void> write(String key, dynamic value) => Future.sync(() {
        _checkOpen('write');
        final bytes = _FileCodec.encode(value, _encoding);
        return _locked('write', () async {
          final file = _fileOf(key);
          final temp = File('${file.path}$_tempExtension');
          await temp.writeAsBytes(bytes, flush: true);
          await temp.rename(file.path);
          _keys.add(key);
          _cachePut(key, bytes);
          if (!HydratedMobX.isVersionKey(key)) await _setUsed(key, file);
        });
      });

  Future<void> _setUsed(String key, File file) async {
    final now = _clock();
    await file.setLastModified(now);
    _usedAt[key] = now.millisecondsSinceEpoch;
  }

  @override
  Future<void> delete(String key) => deleteAll([key]);

  @override
  Future<void> deleteAll(Iterable<String> keys) {
    final list = keys.toList();
    return _locked('delete', () async {
      for (final key in list) {
        if (!_keys.remove(key)) continue;
        _cacheRemove(key);
        _usedAt.remove(key);
        try {
          await _fileOf(key).delete();
        } on PathNotFoundException {
          // Already gone.
        }
      }
    });
  }

  @override
  Future<void> clear() {
    _checkOpen('clear');
    // Suspend the live stores now: a write they queued behind the lock
    // would otherwise land after the wipe.
    HydratedMobX.suspendAll(storage: this);
    return _locked('clear', () async {
      final keys = _keys.toList();
      _keys.clear();
      _cache.clear();
      _cachedBytes = 0;
      _usedAt.clear();
      for (final key in keys) {
        try {
          await _fileOf(key).delete();
        } on PathNotFoundException {
          // Already gone.
        }
      }
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _lock.synchronized(() {
      _closed = true;
      _cache.clear();
      _cachedBytes = 0;
    });
  }

  @override
  void markUsed(String key) {
    if (_closed || HydratedMobX.isVersionKey(key) || !_keys.contains(key)) {
      return;
    }
    final last = _usedAt[key];
    final now = _clock().millisecondsSinceEpoch;
    if (last != null && now - last < _useResolution.inMilliseconds) return;
    _usedAt[key] = now;
    // Best effort: a lost use time only makes the key look older.
    unawaited(
      _lock.synchronized(() async {
        if (_keys.contains(key)) await _setUsed(key, _fileOf(key));
      }).catchError((Object _) {}),
    );
  }

  /// Deletes stale state, with its version key, and returns the state keys
  /// it deleted. A key's use time is when its store last hydrated from it or
  /// wrote it (kept as the file's modification time).
  ///
  /// - [olderThan] drops every key not used for that long.
  /// - [maxEntries] then keeps only that many keys, the most recently used.
  /// - [where] limits both to the keys it accepts; other keys are never
  ///   evicted and do not count towards [maxEntries].
  /// - [keepLive] spares, like [where], the keys of live stores.
  ///
  /// Live stores of evicted keys stop persisting.
  Future<Set<String>> evict({
    Duration? olderThan,
    int? maxEntries,
    bool Function(String key)? where,
    bool keepLive = false,
  }) async {
    if (maxEntries != null && maxEntries < 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be >= 0');
    }
    if (olderThan != null && olderThan.isNegative) {
      throw ArgumentError.value(olderThan, 'olderThan', 'must not be negative');
    }
    final candidates = await _locked('evict', () async {
      final live = keepLive ? HydratedMobX.liveTokens(storage: this) : null;
      return [
        for (final key in _keys.toList())
          if (!HydratedMobX.isVersionKey(key) &&
              !(live?.contains(key) ?? false) &&
              (where?.call(key) ?? true))
            (key: key, usedAt: await _usedAtOf(key)),
      ];
    });
    final now = _clock().millisecondsSinceEpoch;
    final doomed = <String>{};
    if (olderThan != null) {
      final cutoff = now - olderThan.inMilliseconds;
      doomed.addAll([
        for (final c in candidates)
          if (c.usedAt < cutoff) c.key,
      ]);
    }
    if (maxEntries != null) {
      final kept = [
        for (final c in candidates)
          if (!doomed.contains(c.key)) c,
      ]..sort((a, b) => b.usedAt.compareTo(a.usedAt));
      doomed.addAll(kept.skip(maxEntries).map((c) => c.key));
    }
    if (doomed.isEmpty) return const {};
    await HydratedMobX.clearAll(storage: this, where: doomed.contains);
    return doomed;
  }

  Future<int> _usedAtOf(String key) async {
    final known = _usedAt[key];
    if (known != null) return known;
    try {
      final modified = _fileOf(key).lastModifiedSync();
      return _usedAt[key] = modified.millisecondsSinceEpoch;
    } on FileSystemException {
      return _clock().millisecondsSinceEpoch;
    }
  }
}

/// The bytes of a value file: a 4-byte header, then the value.
abstract final class _FileCodec {
  static const _magic = [0x89, 0x48, 0x46]; // 0x89 'H' 'F'
  static const _bytesFormat = 0;
  static const _jsonFormat = 1;
  static const _gzipFormat = 2;
  static const _headerLength = 4;

  static Uint8List encode(Object? value, HydratedEncoding encoding) {
    final int format;
    final List<int> body;
    if (value is Uint8List) {
      format = _bytesFormat;
      body = value;
    } else {
      // Throws for values JSON cannot hold, failing the write.
      final text = utf8.encode(jsonEncode(value));
      final gzipped = encoding == HydratedEncoding.gzipJson;
      format = gzipped ? _gzipFormat : _jsonFormat;
      body = gzipped ? gzip.encode(text) : text;
    }
    return Uint8List(_headerLength + body.length)
      ..setAll(0, _magic)
      ..[3] = format
      ..setAll(_headerLength, body);
  }

  static Object? decode(Uint8List bytes) {
    if (bytes.length < _headerLength ||
        bytes[0] != _magic[0] ||
        bytes[1] != _magic[1] ||
        bytes[2] != _magic[2]) {
      throw const FormatException('Not a hydrated_mobx value file');
    }
    final body = Uint8List.sublistView(bytes, _headerLength);
    return switch (bytes[3]) {
      _bytesFormat => Uint8List.fromList(body),
      _jsonFormat => jsonDecode(utf8.decode(body)),
      _gzipFormat => jsonDecode(utf8.decode(gzip.decode(body))),
      final format => throw FormatException('Unknown value format $format'),
    };
  }
}
