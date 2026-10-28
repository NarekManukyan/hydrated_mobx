# Changelog

## [2.0.0] - 2026-10-29

See "Migrating from 1.x" in the README for the upgrade steps.

### Breaking

- `storagePrefix` is abstract. The `runtimeType` default lost stored state on a
  class rename or an obfuscated build. Return the old class name to keep
  reading 1.x data.
- `clear({resume})` is renamed `clearPersisted({resume})`, freeing `clear` for
  stores' own methods.
- `migrate` returns `Map<String, dynamic>?`; `null` drops the stored state.
- `defaultOnHydrationError` and `defaultOnStorageError` are removed in favour
  of `HydratedMobX.observer`. The constructor's handlers are now optional.
- `Storage` gains `deleteAll` and `keys`. `HydratedMobX.disposeAllForClear()`
  is replaced by `HydratedMobX.suspendAll({storage})`, which suspends only the
  stores bound to that storage.
- Reading, writing or deleting through a closed `HydratedStorage` throws
  `StorageClosedException` (reported to the error handlers) instead of being
  silently ignored.
- The `.hydrated_bloc.json` migration inherited from hydrated_bloc is removed.

### Added

- `persistDelay` (constructor) and `HydratedMobX.defaultPersistDelay`: changes
  within the window are written once. `flush()`, `HydratedMobX.flushAll()`, and
  `dispose()` write the pending state instead of dropping it.
- `HydratedObserver` (`HydratedMobX.observer`): one place for every store's
  hydration errors, storage errors and migrations.
- `storage:` constructor parameter, binding a store to any `Storage`.
- `HydratedStorage.build(boxName:)` for several independent storages.
- Eviction: `HydratedStorage.build(maxAge:, maxEntries:, evictable:,
  trackUse:, useResolution:)` and `HydratedStorage.evict()`, based on use times
  kept in a companion box that only evicting storages open. `evict()` stops
  the live stores of the keys it deletes.
- `HydratedStorage.build(compactionStrategy:)`.
- `HydratedMobX.clearAll({storage, where, resume})` and `deleteToken`: clear a
  whole storage or only matching tokens in one `deleteAll`, suspending the
  affected stores first.
- `HydratedMobX.versionKeySuffix`, `versionKeyOf`, `isVersionKey`,
  `tokenOfKey`.
- `trustToJson`: skip the serialization walk for a `toJson` that already
  returns plain JSON.
- `InMemoryStorage` for tests, and `ForwardingStorage` to wrap a storage
  (it suspends its own stores on `clear` and forwards eviction use times).
- `UseTrackingStorage.markUsed`: hydrating a key counts as using it for
  eviction; a plain `read` does not.
- `HydratedMobX.rebindAll(from:, to:)` moves live stores to a rebuilt storage.
- `HydratedJson.readStringList`; `importData(storage:)`.
- `benchmark/persistence_benchmark.dart`.
- The example app shows every feature, one screen each.

### Changed

- A change that leaves the JSON equal to what was last written or hydrated is
  not written. Creating a store over stored state no longer writes it back.
- `fromJson` receives a fresh deep copy; the storage's cached value is no
  longer modified in place.
- Serialization errors go to the storage error handler instead of MobX's
  reaction log, and no longer leave the cycle detector in a bad state.
- An empty list in `toJson` is copied, not kept by reference.
- `HydratedJson.readList` and `readObject` accept maps with any key type and
  convert them deeply.
- Storage locks are per instance, and building different boxes runs in
  parallel.
- Storage writes and error callbacks run untracked, so a storage or observer
  that reads observables never becomes a dependency of the persistence
  reaction.

## [1.2.0] - 2026-08-21

### Added

- **Schema versioning + `migrate` hook.** `HydratedMobX` now exposes an
  overridable `int get version` (default `1`) and
  `Map<String, dynamic> migrate(int oldVersion, Map<String, dynamic> oldState)`
  (default: identity). When a store hydrates data written under a lower version,
  `migrate` is invoked to upgrade it, the result is passed to `fromJson`, and the
  new schema version is recorded — stamped only after the state that produced it
  has been written, so the version can never lead the state and skip a required
  migration. Data written before this release has no version key and is treated
  as version 1; `clear()` deletes the version key alongside the state.
- **`HydratedMobX.importData(...)`** — a static helper to seed hydrated storage
  with data imported from another persistence layer (e.g. `SharedPreferences`, a
  legacy Hive box, or a previous key scheme) before constructing stores. Existing
  keys are preserved by default; pass `overwrite: true` to replace them. Pass
  `version:` to tag imported data so a versioned store does not re-migrate data
  that is already current.
- **`OnStorageError` callback.** `HydratedMobX` now accepts an `onStorageError`
  handler (constructor and `hydrate`) invoked when persisting a state change
  fails. Persistence is fire-and-forget, so this is the only way to observe such
  failures (e.g. to forward them to a crash reporter). Defaults to
  `defaultOnStorageError`, which preserves the previous log-only behavior.
- **`dispose()`** — permanently stops a store from persisting and removes it
  from the internal instance registry so it can be garbage collected. Call it
  when a store is no longer used (the on-disk state is left untouched).
- The internal instance registry now holds `WeakReference`s and prunes entries
  via a `Finalizer`, so stores no longer leak once their persistence reaction is
  released (via `clear()`, `dispose()`, or a `Storage`-level clear) and the app
  drops them — even without an explicit `dispose()`. Calling `dispose()` is
  still preferred to release the reaction immediately.
- **`clear({bool resume = false})`** — `clear` now takes an optional `resume`
  flag. `resume: true` keeps persisting after the wipe (subsequent changes are
  saved again), matching `hydrated_bloc`. The default (`false`) preserves the
  existing behavior of stopping persistence after a clear.
- Expanded the test suite to cover schema migration, `importData`,
  `onStorageError`, `dispose`, `clear(resume: true)`, and re-`hydrate`.

### Changed

- Raised the minimum Dart SDK from `2.14.0` to `3.0.0`.
- Documented why `HydratedStorage.read` is intentionally not lock-guarded (it is
  a synchronous in-memory lookup that cannot interleave with mutating ops on
  Dart's single-threaded event loop), and why the `hive_ce/src/hive_impl.dart`
  implementation import is unavoidable (no public `HiveImpl`).

- Added `topics` to `pubspec.yaml` (`mobx`, `state-management`, `persistence`,
  `storage`, `hydration`) for pub.dev discoverability, and the example now
  disposes its stores from `State.dispose` to model the recommended lifecycle.

### Fixed

- Calling `hydrate()` more than once no longer leaks the previous persistence
  reaction or double-writes: the prior reaction is disposed before re-arming.

## [1.1.4] - 2026-04-08

### Added

- Comprehensive test suite expanded from 4 to 59 tests across 14 groups, covering hydration edge cases (empty storage, corrupt JSON, `HydrationErrorBehavior.retain`), `storageToken` composition, autorun persistence, `store.clear()` / `HydratedStorage.clear()`, nested map/list serialization, cyclic and unsupported value errors, concurrent writes, encrypted storage via `HydratedAesCipher`, and full `HydratedJson` reader/writer coverage.

## [1.1.3] - 2026-03-12

### Added

- **Optional `storeId` parameter** on `HydratedMobX`: pass a per-instance storage key (e.g. `super(storeId: meetingId)`) so hydration uses the correct key before subclass fields are initialized. Works with dependency injection (e.g. injectable, get_it).
- **`HydratedJson` helpers** for type-safe `fromJson`/`toJson`: `readList`, `readObject`, `readString`, `readInt`, `readDouble`, `readBool`, `writeList`. They return safe defaults when keys are missing or types are wrong, so you can avoid manual type checks and try/catch.
- Example app: **KeyedCounterStore** and keyed counter page demonstrating per-instance storage with `storeId`.

### Changed

- Constructor is now the first member of `HydratedMobX` (linter compliance).
- Documentation and example snippets updated for the `storeId` pattern and `HydratedJson` usage.
- Resolved all analyzer/linter issues in `lib/` (comment references, line length, sort order).

### Note (medium risk)

- The optional `storeId` parameter touches **core persistence key generation**. The storage key is `storagePrefix + (storeId ?? id)`. Stores that do not pass `storeId` are unchanged (they still use `id`). If you rely on custom `id` logic or override storage keys, verify hydration/persistence behavior after upgrading. Other changes in this release are additive (HydratedJson, docs, example, iOS config).

## [1.1.2] - 2024-04-17

### Fixed
- Fixed example project to work with latest API changes
- Updated example dependencies to latest versions

## [1.1.1] - 2024-04-17

### Fixed
- Fixed dependency version constraints for better compatibility
- Resolved potential race conditions in state persistence
- Improved error handling for storage operations

## [1.1.0] - 2024-04-17

### Changed
- Breaking: Changed `HydratedMobX` from a mixin to an abstract class
  - Now use `extends HydratedMobX` instead of `with HydratedMobX`
  - This change provides better type safety and clearer inheritance structure

## [1.0.1] - 2024-04-16

### Added
- Enhanced JSON serialization support with proper type handling
- Support for complex object serialization through `toJson` methods
- Circular reference detection and prevention
- Improved error handling for unsupported types
- Better type safety in JSON conversion

### Changed
- Refactored JSON serialization implementation for better reliability
- Improved error messages for serialization failures

## [1.0.0] - 2024-04-15

### Added
- Initial release of HydratedMobX
- Automatic persistence and restoration of MobX stores
- Support for encryption
- Cross-platform support (iOS, Android, Web, Linux, macOS, Windows)
- Integration with Hive for efficient storage
