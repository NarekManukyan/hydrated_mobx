import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:hydrated_mobx/src/eviction.dart';
import 'package:hydrated_mobx/src/hydrated_encoding.dart';
import 'package:hydrated_mobx/src/hydrated_mobx.dart';
import 'package:hydrated_mobx/src/hydrated_storage.dart';
import 'package:hydrated_mobx/src/pending_deletes.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';

/// {@template file_storage}
/// A [Storage] that keeps each key in its own file and nothing in memory
/// until it is read, for per-id state (one store per document, chat or
/// note) that should cost no RAM while its store does not exist.
///
/// A `HydratedStorage` box holds every value in memory for as long as it is
/// open, so its memory grows with what is on disk. Here, opening lists the
/// directory and reads no file (evicting at build, with `maxAge` or
/// `maxEntries`, also reads their modification times), and memory holds the
/// values that were read or written lately, up to `cacheBytes`.
///
/// [read] stays synchronous, as stores need: a value that is not cached is
/// read from its file right there, which blocks for as long as the read
/// takes. Call [preload] first on paths where that matters, e.g. while
/// navigating to the screen that creates the store:
///
/// ```dart
/// final notes = await FileStorage.build(
///   storageDirectory: HydratedStorageDirectory('${support.path}/notes'),
/// );
///
/// await notes.preload('note_$id');
/// final store = NoteStore(id, storage: notes); // hydrates from the cache
/// ```
///
/// A write goes to a temporary file that is then renamed over the old one,
/// so a crash leaves the old value or the new one, never a torn file.
/// [deleteAll] and [clear] delete one file at a time, state keys before
/// their version keys, so a crash midway leaves some keys behind but never
/// state without its version key. Values are JSON (or bytes), as
/// [HydratedEncoding.json] or [HydratedEncoding.gzipJson], and are not
/// encrypted. One storage at a time may use a directory: a second one, from
/// this isolate or another process, fails to build. Isolates of one process
/// share its file lock and do not share statics, so the app must keep a
/// directory to one isolate. The lock is held until [close]; iOS terminates
/// a suspended app that holds a file lock in an app-group container, so
/// close a storage kept there when the app goes to the background. Not
/// available on the web.
/// {@endtemplate}
class FileStorage implements UseTimeStorage {
  FileStorage._(
    this._directory,
    this._keys,
    this._lock,
    this._lockFile, {
    required HydratedEncoding encoding,
    required int cacheBytes,
    required Duration useResolution,
    required DateTime Function() clock,
  })  : _codec = HydratedValueCodec.file(encoding),
        _cacheLimit = cacheBytes,
        _useResolution = useResolution,
        _clock = clock;

  /// The `cacheBytes` used when none is given to [build].
  static const defaultCacheBytes = 8 << 20;

  /// Extension of the file that holds a key.
  static const _extension = '.hyd';

  /// Extension of a value being written, before it is renamed into place.
  static const _tempExtension = '.tmp';

  /// The file held locked while a storage uses its directory.
  static const _lockName = '.lock';

  /// The longest file name most file systems accept is 255 bytes.
  static const _maxNameLength = 255;

  /// Lowercase base32 (RFC 4648), so names stay distinct on file systems
  /// that ignore case, as macOS and Windows do by default.
  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

  /// Directories this isolate has open. A file lock is held per process, so
  /// it cannot tell two storages of one isolate apart; neither can tell two
  /// isolates of one process apart.
  static final _openDirectories = <String>{};

  /// Opens the storage kept in [storageDirectory], creating it if needed.
  ///
  /// - [encoding] is how values are written: [HydratedEncoding.gzipJson]
  ///   (the default, smallest) or [HydratedEncoding.json]. Files written
  ///   either way read back whatever the setting.
  /// - [cacheBytes] bounds the encoded bytes kept in memory, most recently
  ///   used first. A value larger than that is never cached.
  /// - [maxAge], [maxEntries] and [evictable] evict as with
  ///   `HydratedStorage.build`, when the storage opens: see [evict].
  /// - [useResolution]: how often a file's use time is rewritten at most,
  ///   by a [write] or by [markUsed].
  ///
  /// Opening lists the directory and reads no file. With [maxAge] or
  /// [maxEntries] it also evicts, which reads the modification time of every
  /// file [evictable] accepts: one `stat` per file, at each launch, run in
  /// a background isolate.
  ///
  /// Throws a [StateError] when another storage, in this isolate or another
  /// process, has the directory open. Another isolate of this process is not
  /// detected: keep each directory to one isolate.
  static Future<FileStorage> build({
    required HydratedStorageDirectory storageDirectory,
    HydratedEncoding encoding = HydratedEncoding.gzipJson,
    int cacheBytes = defaultCacheBytes,
    Duration? maxAge,
    int? maxEntries,
    bool Function(String key)? evictable,
    Duration useResolution = HydratedStorage.defaultUseResolution,
    @visibleForTesting DateTime Function() clock = DateTime.now,
  }) async {
    if (storageDirectory == HydratedStorageDirectory.web) {
      throw ArgumentError.value(
        storageDirectory,
        'storageDirectory',
        'must be a directory; FileStorage is not available on the web',
      );
    }
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
    checkEvictArguments(
      olderThan: maxAge,
      maxEntries: maxEntries,
      olderThanName: 'maxAge',
    );
    final dir = Directory(storageDirectory.path);
    await dir.create(recursive: true);
    final path = await dir.resolveSymbolicLinks();
    if (!_openDirectories.add(path)) {
      throw StateError('A FileStorage already has $path open');
    }
    final RandomAccessFile lockFile;
    try {
      lockFile = await _lockDirectory(path);
    } catch (_) {
      _openDirectories.remove(path);
      rethrow;
    }
    final keys = <String>{};
    final storage = FileStorage._(
      Directory(path),
      keys,
      Lock(),
      lockFile,
      encoding: encoding,
      cacheBytes: cacheBytes,
      useResolution: useResolution,
      clock: clock,
    );
    try {
      await for (final entry in storage._directory.list()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (name.endsWith(_tempExtension)) {
          // A write the process did not finish; the old value is intact.
          // Only this storage's own: the directory may hold other files.
          final target = name.substring(0, name.length - _tempExtension.length);
          if (_keyOf(target) != null) await entry.delete();
        } else if (_keyOf(name) case final key?) {
          keys.add(key);
        }
      }
      if (maxAge != null || maxEntries != null) {
        await storage.evict(
          olderThan: maxAge,
          maxEntries: maxEntries,
          where: evictable,
        );
      }
    } catch (_) {
      await storage.close();
      rethrow;
    }
    return storage;
  }

  static Future<RandomAccessFile> _lockDirectory(String path) async {
    final file = await File('$path${Platform.pathSeparator}$_lockName')
        .open(mode: FileMode.write);
    try {
      // Exclusive and non-blocking: fails at once if another process holds it.
      return await file.lock();
    } on FileSystemException {
      await file.close();
      throw StateError('Another process has the FileStorage at $path open');
    }
  }

  final Directory _directory;
  final HydratedValueCodec _codec;
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

  final Lock _lock;
  final RandomAccessFile _lockFile;
  bool _closed = false;

  /// Keys a queued [deleteAll] or [clear] will remove, which [read] and
  /// [keys] treat as gone already.
  final _pending = PendingDeletes();

  static String _nameOf(String key) {
    final bytes = utf8.encode(key);
    // A state key's version key, written beside it, has the longer name,
    // and a write adds the temporary extension to either.
    final longest = HydratedMobX.isVersionKey(key)
        ? bytes.length
        : bytes.length + HydratedMobX.versionKeySuffix.length;
    if (_base32Length(longest) + _extension.length + _tempExtension.length >
        _maxNameLength) {
      throw ArgumentError.value(key, 'key', 'is too long for a file name');
    }
    return '${_base32(bytes)}$_extension';
  }

  static int _base32Length(int bytes) => (bytes * 8 + 4) ~/ 5;

  static String _base32(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 31]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static String? _keyOf(String name) {
    if (!name.endsWith(_extension)) return null;
    final bytes = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final char
        in name.substring(0, name.length - _extension.length).split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) return null; // Not a file this storage wrote.
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        bytes.add((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    // Padding bits a name of this storage never sets.
    if (bits >= 5 || buffer != 0) return null;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
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
    if (!_keys.contains(key) || _pending.hides(key)) return null;
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
    return _codec.decode(bytes);
  }

  @override
  Iterable<String> get keys {
    _checkOpen('list keys');
    return [
      for (final key in _keys)
        if (!_pending.hides(key)) key,
    ];
  }

  @override
  Future<void> write(String key, dynamic value) => Future.sync(() {
        _checkOpen('write');
        final bytes = _codec.encode(value)! as Uint8List;
        return _locked('write', () async {
          final file = _fileOf(key);
          final temp = File('${file.path}$_tempExtension');
          await temp.writeAsBytes(bytes, flush: true);
          await temp.rename(file.path);
          _keys.add(key);
          _cachePut(key, bytes);
          // The rename left the file the time of this write. Its use time is
          // set as the clock reads it, and at most once per use resolution,
          // as [markUsed] does.
          if (_dueStamp(key)) await _setUsed(key, file);
        });
      });

  /// Whether [key] is a state key whose use time was not recorded within
  /// the use resolution.
  bool _dueStamp(String key) => isUseDue(
        key,
        last: _usedAt[key],
        now: _clock().millisecondsSinceEpoch,
        resolution: _useResolution,
      );

  Future<void> _setUsed(String key, File file) async {
    final now = _clock();
    await file.setLastModified(now);
    _usedAt[key] = now.millisecondsSinceEpoch;
  }

  @override
  Future<void> delete(String key) => deleteAll([key]);

  @override
  Future<void> deleteAll(Iterable<String> keys) {
    _checkOpen('delete');
    final list = keys.toList();
    return _pending.delete(
      list,
      () => _locked('delete', () => _deleteFiles(list.where(_keys.contains))),
    );
  }

  /// Deletes the files of [keys], state keys first: a crash midway then
  /// never leaves state without its version key, which would make it read
  /// as version 1. A key is forgotten only once its file is gone, so after
  /// a failed delete it is still listed, and a retry reaches it.
  Future<void> _deleteFiles(Iterable<String> keys) async {
    final list = keys.toList();
    final ordered = [
      ...list.where((key) => !HydratedMobX.isVersionKey(key)),
      ...list.where(HydratedMobX.isVersionKey),
    ];
    for (final key in ordered) {
      try {
        await _fileOf(key).delete();
      } on PathNotFoundException {
        // Already gone.
      }
      _keys.remove(key);
      _cacheRemove(key);
      _usedAt.remove(key);
    }
  }

  @override
  Future<void> clear() {
    _checkOpen('clear');
    // Suspend the live stores now: a write they queued behind the lock
    // would otherwise land after the wipe.
    HydratedMobX.suspendAll(storage: this);
    return _pending.clear(
      () => _locked('clear', () => _deleteFiles(_keys.toList())),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _lock.synchronized(() async {
      if (_closed) return;
      _closed = true;
      _cache.clear();
      _cachedBytes = 0;
      // Closing releases the lock; only then may this isolate open the
      // directory again.
      try {
        await _lockFile.close();
      } finally {
        _openDirectories.remove(_directory.path);
      }
    });
  }

  @override
  DateTime? usedAt(String key) {
    _checkOpen('read use times');
    if (HydratedMobX.isVersionKey(key) ||
        !_keys.contains(key) ||
        _pending.hides(key)) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(_usedAtOf(key));
  }

  /// Records [time], or now if it is later, as [key]'s use time, when this
  /// storage holds [key].
  @override
  Future<void> setUsedAt(String key, DateTime time) =>
      _locked('set use times', () async {
        if (HydratedMobX.isVersionKey(key) || !_keys.contains(key)) return;
        final at = useTimeAt(
          time.millisecondsSinceEpoch,
          _clock().millisecondsSinceEpoch,
        );
        await _fileOf(key)
            .setLastModified(DateTime.fromMillisecondsSinceEpoch(at));
        _usedAt[key] = at;
      });

  @override
  void markUsed(String key) {
    if (_closed || HydratedMobX.isVersionKey(key) || !_keys.contains(key)) {
      return;
    }
    if (!_dueStamp(key)) return;
    _usedAt[key] = _clock().millisecondsSinceEpoch;
    // Best effort: a lost use time only makes the key look older.
    unawaited(
      _lock.synchronized(() async {
        // close() may have run while this waited, and released the directory.
        if (!_closed && _keys.contains(key)) await _setUsed(key, _fileOf(key));
      }).catchError((Object _) {}),
    );
  }

  /// Deletes stale state, with its version key, and returns a new set of
  /// the state keys it deleted. A key's use time is when its store last
  /// hydrated from it or wrote it (kept as the file's modification time).
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
    checkEvictArguments(olderThan: olderThan, maxEntries: maxEntries);
    // Under the lock, so use times queued by [markUsed] land first.
    final doomed = await _locked('evict', () async {
      final accepted = [
        for (final key in _keys.toList())
          if (!HydratedMobX.isVersionKey(key) && (where?.call(key) ?? true))
            key,
      ];
      await _loadUseTimes(accepted);
      return evictionsAmong(
        accepted,
        usedAt: _usedAtOf,
        now: _clock().millisecondsSinceEpoch,
        olderThan: olderThan,
        maxEntries: maxEntries,
        live: keepLive ? () => HydratedMobX.liveTokens(storage: this) : null,
      );
    });
    if (doomed.isEmpty) return doomed;
    await HydratedMobX.clearAll(storage: this, where: doomed.contains);
    return doomed;
  }

  /// Reads the modification times of the files of [keys] not known yet in
  /// one background isolate, so that evicting a large directory at build
  /// does not block this isolate for a stat per file.
  Future<void> _loadUseTimes(List<String> keys) async {
    final unknown = [
      for (final key in keys)
        if (!_usedAt.containsKey(key)) key,
    ];
    if (unknown.isEmpty) return;
    final paths = [for (final key in unknown) _fileOf(key).path];
    final times = await Isolate.run(() => _modifiedTimes(paths));
    for (final (i, key) in unknown.indexed) {
      if (times[i] case final time?) _usedAt[key] = time;
    }
  }

  /// The modification time (ms since epoch) of each file in [paths], `null`
  /// for one that cannot be read.
  static List<int?> _modifiedTimes(List<String> paths) => [
        for (final path in paths)
          () {
            try {
              return File(path).lastModifiedSync().millisecondsSinceEpoch;
            } on FileSystemException {
              return null;
            }
          }(),
      ];

  int _usedAtOf(String key) {
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
