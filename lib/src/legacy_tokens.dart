import 'package:hydrated_mobx/src/hydrated_mobx.dart';
import 'package:meta/meta.dart';

/// {@template legacy_store}
/// A store that hydrated_mobx 1.x keyed by its `runtimeType`, and the shape
/// of the state it writes, so [LegacyTokens.match] can find its old key.
/// {@endtemplate}
@immutable
class LegacyStore {
  /// {@macro legacy_store}
  const LegacyStore({
    required this.prefix,
    required this.keys,
    this.legacyPrefix,
    this.requiredKeys,
    this.idPattern,
  });

  /// The fixed [HydratedMobX.storagePrefix] the store uses now.
  final String prefix;

  /// The 1.x prefix, `'$Type'`. In an obfuscated build it is the class name
  /// this build gave the type, which matches the old key only when the build
  /// that wrote it chose the same name. `null` matches by shape only.
  final String? legacyPrefix;

  /// Every top-level key the store's `toJson` writes. A value with any other
  /// key is not this store's.
  final List<String> keys;

  /// The [keys] every value of this store has. Defaults to the first of
  /// [keys].
  final List<String>? requiredKeys;

  /// For a store with one key per id (per note, per chat), the ids its token
  /// can end with, e.g. `RegExp('[0-9a-f]{32}')`. `null` for a store with a
  /// single key.
  final RegExp? idPattern;

  /// Whether the store has one key per id.
  bool get keyed => idPattern != null;

  /// Whether [value] has the shape of this store's state.
  bool owns(Object? value) {
    if (value is! Map) return false;
    final required = requiredKeys ?? keys.take(1);
    return required.every(value.containsKey) && value.keys.every(keys.contains);
  }
}

/// Finds the new token of state that hydrated_mobx 1.x keyed by
/// `runtimeType`, for [HydratedMobX.moveTokens].
abstract final class LegacyTokens {
  /// A Dart class name, which is what 1.x keys started with.
  static final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

  /// Returns a `to` for [HydratedMobX.moveTokens] that moves the state of
  /// [stores] off their 1.x keys:
  ///
  /// ```dart
  /// await HydratedMobX.moveTokens(LegacyTokens.match([
  ///   LegacyStore(prefix: 'user', legacyPrefix: '$UserStore',
  ///       keys: ['currentUser', 'settings']),
  ///   LegacyStore(prefix: 'chat_', legacyPrefix: '$ChatStore',
  ///       keys: ['messages'], idPattern: RegExp('[0-9a-f]{32}')),
  /// ]));
  /// ```
  ///
  /// Outside obfuscated builds `'$Type'` is the class name the 1.x key was
  /// made from, and keys are found by it. An obfuscated build renames classes
  /// whenever the code around them changes, so a key is also matched by
  /// shape: a key that looks like a class name (followed by an id the
  /// store's [LegacyStore.idPattern] accepts, for a keyed store) whose value
  /// has the shape of exactly one store.
  ///
  /// Both ways require the value to have the store's shape, so a name this
  /// build gave to a different class never moves one store's state onto
  /// another. Keys starting with a store's current prefix or one of
  /// [reservedPrefixes] are never moved.
  static String? Function(String token, Object? value) match(
    List<LegacyStore> stores, {
    Iterable<String> reservedPrefixes = const [],
  }) {
    final owned = [
      for (final store in stores) store.prefix,
      ...reservedPrefixes,
    ];
    // Backtracks so the class name ends where an id starts, whatever
    // characters the two share.
    final keyedTokens = {
      for (final store in stores)
        if (store.idPattern case final id?)
          store: RegExp(
            '^${_identifier.pattern}(${id.pattern})\$',
            caseSensitive: id.isCaseSensitive,
          ),
    };
    return (token, value) {
      if (owned.any(token.startsWith)) return null;
      final candidates = [
        for (final store in stores)
          if (store.owns(value)) store,
      ];
      for (final store in candidates) {
        final legacy = store.legacyPrefix;
        if (legacy == null || !token.startsWith(legacy)) continue;
        final id = token.substring(legacy.length);
        if (store.keyed || id.isEmpty) return '${store.prefix}$id';
      }
      if (candidates.length != 1) return null;
      final store = candidates.single;
      final keyed = keyedTokens[store]?.firstMatch(token);
      if (keyed != null) return '${store.prefix}${keyed.group(1)}';
      // A store with a single key, or a keyed store built without an id.
      final name = _identifier.matchAsPrefix(token);
      return name?.end == token.length ? store.prefix : null;
    };
  }
}
