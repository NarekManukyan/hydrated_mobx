import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import 'counting_storage.dart';

/// Box names; Hive stores each as `<name>.hive` in the storage directory.
const kSessionBox = 'session';
const kAccountBox = 'account';
const kRecentBox = 'recent';
const kVaultBox = 'vault';

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

  static Future<AppStorages> build(String directory) async {
    final dir = HydratedStorageDirectory(directory);
    // Each box has its own build lock, so they open side by side.
    final (main, session, account, recent, vault) = await (
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
    ).wait;
    return AppStorages._(
      directory: directory,
      main: CountingStorage(main),
      session: session,
      account: account,
      recent: recent,
      vault: vault,
    );
  }

  /// Closes and reopens the recent box, which runs its eviction again.
  Future<void> rebuildRecent() async {
    final path = directory;
    if (path == null) return;
    final old = recent;
    await HydratedMobX.flushAll(storage: old);
    await old.close();
    recent = await _buildRecent(HydratedStorageDirectory(path));
    // Stores still open on the old box (the pinned note) carry on here.
    HydratedMobX.rebindAll(from: old, to: recent);
  }

  static Future<Storage> _buildRecent(HydratedStorageDirectory dir) =>
      HydratedStorage.build(
        storageDirectory: dir,
        boxName: kRecentBox,
        maxEntries: kRecentMaxEntries,
        // Seconds, not the default minute, so a quick demo sees the order.
        useResolution: const Duration(seconds: 1),
        // Only the cache entries age out; the pinned note never does.
        evictable: (key) => key.startsWith(kRecentPrefix),
      );

  /// Every storage by display name, for the inspector. Getters, since the
  /// recent box is replaced when it is rebuilt.
  Map<String, Storage Function()> get all => {
        'main (hydrated_box)': () => main,
        kSessionBox: () => session,
        kAccountBox: () => account,
        kRecentBox: () => recent,
        kVaultBox: () => vault,
      };
}

/// Set in `main` before `runApp`.
late AppStorages appStorages;
