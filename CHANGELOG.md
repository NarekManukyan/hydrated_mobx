# Changelog

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
