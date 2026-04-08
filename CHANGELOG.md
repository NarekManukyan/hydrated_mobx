# Changelog

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
