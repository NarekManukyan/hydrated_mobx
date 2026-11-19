import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hydrated_mobx/file_storage.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import 'counting_storage.dart';

/// Box names; Hive stores each as `<name>.hive` in the storage directory.
const kSessionBox = 'session';
const kAccountBox = 'account';
const kRecentBox = 'recent';
const kVaultBox = 'vault';
const kLargeNotesBox = 'large_notes';

/// The directory, under the storage directory, of the one-file-per-key
/// storage.
const kLargeNotesDirectory = 'large_notes';

/// The recent-items box keeps at most this many `recent_` entries.
const kRecentMaxEntries = 5;
const kRecentPrefix = 'recent_';

/// Demo only: a real app keeps the key in the platform keychain.
const _kVaultPassword = 'hydrated-mobx-demo';

/// Every storage the demo uses, one per namespace.
class AppStorages {
  AppStorages._({
    required this.main,
    required this.session,
    required this.account,
    required this.recent,
    required this.vault,
    required this.largeNotesBox,
    required this.largeNotesFiles,
    this.directory,
  });

  /// In-memory storages, for widget tests.
  AppStorages.inMemory()
    : this._(
        main: CountingStorage(InMemoryStorage()),
        session: InMemoryStorage(),
        account: InMemoryStorage(),
        recent: InMemoryStorage(),
        vault: InMemoryStorage(),
        largeNotesBox: InMemoryStorage(),
        largeNotesFiles: InMemoryStorage(),
      );

  /// The directory the Hive boxes live in; null in memory.
  final String? directory;

  /// The default box (`HydratedMobX.storage`), wrapped to count writes.
  final CountingStorage main;

  /// Cleared on sign-out.
  final Storage session;

  /// Survives sign-out.
  final Storage account;

  /// A capped cache of recently viewed items; rebuilt by the eviction page.
  Storage recent;

  /// AES-256 encrypted.
  final Storage vault;

  /// The large notes kept in a box, gzipped rather than decoded.
  final Storage largeNotesBox;

  /// The large notes kept one file per key, nothing in memory until read.
  final Storage largeNotesFiles;

  static Future<AppStorages> build(String directory) async {
    final dir = HydratedStorageDirectory(directory);
    // Each box has its own build lock, so they open side by side.
    final (
      main,
      session,
      account,
      recent,
      vault,
      largeNotesBox,
      largeNotesFiles,
    ) = await (
      HydratedStorage.build(storageDirectory: dir),
      HydratedStorage.build(storageDirectory: dir, boxName: kSessionBox),
      HydratedStorage.build(storageDirectory: dir, boxName: kAccountBox),
      _buildRecent(dir),
      HydratedStorage.build(
        storageDirectory: dir,
        boxName: kVaultBox,
        encryptionCipher: HydratedAesCipher(
          sha256.convert(utf8.encode(_kVaultPassword)).bytes,
        ),
      ),
      HydratedStorage.build(
        storageDirectory: dir,
        boxName: kLargeNotesBox,
        encoding: HydratedEncoding.gzipJson,
      ),
      FileStorage.build(
        storageDirectory: HydratedStorageDirectory(
          '$directory/$kLargeNotesDirectory',
        ),
      ),
    ).wait;
    return AppStorages._(
      directory: directory,
      main: CountingStorage(main),
      session: session,
      account: account,
      recent: recent,
      vault: vault,
      largeNotesBox: largeNotesBox,
      largeNotesFiles: largeNotesFiles,
    );
  }

  /// Closes and reopens the recent box, then evicts down to
  /// [kRecentMaxEntries].
  ///
  /// The new box only tracks use at build. Evicting there would run before
  /// the pinned note's store moves over, so a store whose key was evicted
  /// would write it straight back; [HydratedStorage.evict] after
  /// [HydratedMobX.rebindAll] suspends it instead.
  Future<void> rebuildRecent() async {
    final path = directory;
    if (path == null) return;
    final old = recent;
    await HydratedMobX.flushAll(storage: old);
    await old.close();
    final HydratedStorage rebuilt;
    try {
      rebuilt = await _buildRecent(
        HydratedStorageDirectory(path),
        evictAtBuild: false,
      );
    } catch (_) {
      // Keep `recent` open, so the page and its stores still work.
      recent = InMemoryStorage();
      HydratedMobX.rebindAll(from: old, to: recent);
      rethrow;
    }
    recent = rebuilt;
    HydratedMobX.rebindAll(from: old, to: rebuilt);
    await rebuilt.evict(
      maxEntries: kRecentMaxEntries,
      where: (key) => key.startsWith(kRecentPrefix),
    );
  }

  /// At launch the box evicts as it opens; [rebuildRecent] evicts after.
  static Future<HydratedStorage> _buildRecent(
    HydratedStorageDirectory dir, {
    bool evictAtBuild = true,
  }) => HydratedStorage.build(
    storageDirectory: dir,
    boxName: kRecentBox,
    trackUse: true,
    maxEntries: evictAtBuild ? kRecentMaxEntries : null,
    // Seconds, not the default minute, so a quick demo sees the order.
    useResolution: const Duration(seconds: 1),
    // Only the cache entries age out; the pinned note never does.
    evictable: (key) => key.startsWith(kRecentPrefix),
  );

  /// Every storage by display name, for the inspector. Getters, since the
  /// recent box is replaced when it is rebuilt. A storage of large values
  /// is listed by key only, without reading them.
  Map<String, ({Storage Function() storage, bool large})> get all => {
    'main (hydrated_box)': (storage: () => main, large: false),
    kSessionBox: (storage: () => session, large: false),
    kAccountBox: (storage: () => account, large: false),
    kRecentBox: (storage: () => recent, large: false),
    kVaultBox: (storage: () => vault, large: false),
    kLargeNotesBox: (storage: () => largeNotesBox, large: true),
    '$kLargeNotesDirectory (files)': (
      storage: () => largeNotesFiles,
      large: true,
    ),
  };
}

/// Set in `main` before `runApp`.
late AppStorages appStorages;
