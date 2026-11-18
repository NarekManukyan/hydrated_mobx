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
    required this.fields,
    this.legacyPrefix,
    this.requiredFields,
    this.idPattern,
  });

  /// The fixed [HydratedMobX.storagePrefix] the store uses now.
  final String prefix;

  /// The 1.x prefix, `'$Type'`. In an obfuscated build it is the class name
  /// this build gave the type, which matches the old key only when the build
  /// that wrote it chose the same name. `null` matches by shape only.
  final String? legacyPrefix;

  /// Every top-level field the store's `toJson` writes. A value with any
  /// other field is not this store's.
  final List<String> fields;

  /// The [fields] every value of this store has. Defaults to the first of
  /// [fields].
  final List<String>? requiredFields;

  /// For a store with one key per id (per note, per chat), the ids its token
  /// can end with, e.g. `RegExp('[0-9a-f]{32}')`. `null` for a store with a
  /// single key.
  final RegExp? idPattern;

  /// Whether [value] has the shape of this store's state.
  bool _owns(Object? value) {
    if (value is! Map) return false;
    final required = requiredFields ?? fields.take(1);
    return required.every(value.containsKey) &&
        value.keys.every(fields.contains);
  }
}

/// Finds the new token of state that hydrated_mobx 1.x keyed by
/// `runtimeType`, for [HydratedMobX.moveTokens].
abstract final class LegacyTokens {
  /// A Dart class name, which is what 1.x keys started with.
  static final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

  /// The shortest class name that leaves a valid id after it.
  static const _shortestIdentifier = r'[A-Za-z_$][A-Za-z0-9_$]*?';

  /// Returns a `to` for [HydratedMobX.moveTokens] that moves the state of
  /// [stores] off their 1.x keys:
  ///
  /// ```dart
  /// await HydratedMobX.moveTokens(LegacyTokens.match([
  ///   LegacyStore(prefix: 'user', legacyPrefix: '$UserStore',
  ///       fields: ['currentUser', 'settings']),
  ///   LegacyStore(prefix: 'chat_', legacyPrefix: '$ChatStore',
  ///       fields: ['messages'], idPattern: RegExp('[0-9a-f]{32}')),
  /// ]));
  /// ```
  ///
  /// Outside obfuscated builds `'$Type'` is the class name the 1.x key was
  /// made from, and keys are found by it. An obfuscated build renames classes
  /// whenever the code around them changes, so a key is also matched by
  /// shape: a key that looks like a class name (followed by an id the
  /// store's [LegacyStore.idPattern] accepts, for a keyed store) whose value
  /// has the shape of exactly one store. Where the name could end in
  /// characters the id also accepts, the longest such id is taken: with
  /// `RegExp(r'\d+')`, `Qz123` is id `123`.
  ///
  /// Both ways require the value to have the store's shape, and for a keyed
  /// store the rest of the key to be an id [LegacyStore.idPattern] accepts,
  /// or nothing: a key without an id moves to the store's [LegacyStore.prefix]
  /// alone, the token of that store built without a `storeId`. So a name
  /// this build gave to a different class never moves one listed store's
  /// state onto another. Keys starting with
  /// a store's current prefix or one of [reservedPrefixes] are never read or
  /// moved.
  static String? Function(String token, Object? Function() value) match(
    List<LegacyStore> stores, {
    Iterable<String> reservedPrefixes = const [],
  }) {
    final owned = [
      for (final store in stores) store.prefix,
      ...reservedPrefixes,
    ];
    RegExp like(RegExp id, String pattern) => RegExp(
          pattern,
          caseSensitive: id.isCaseSensitive,
          unicode: id.isUnicode,
          dotAll: id.isDotAll,
          multiLine: id.isMultiLine,
        );
    // Whole ids, for keys found by name.
    final ids = {
      for (final store in stores)
        if (store.idPattern case final id?)
          store: like(id, '^(?:${id.pattern})\$'),
    };
    // A class name and an id. The name is as short as it can be, so the id
    // is as long as the pattern allows, whatever characters the two share.
    final keyedTokens = {
      for (final store in stores)
        if (store.idPattern case final id?)
          store: like(id, '^$_shortestIdentifier(${id.pattern})\$'),
    };
    return (token, read) {
      if (owned.any(token.startsWith)) return null;
      final value = read();
      final candidates = [
        for (final store in stores)
          if (store._owns(value)) store,
      ];
      for (final store in candidates) {
        final legacy = store.legacyPrefix;
        if (legacy == null || !token.startsWith(legacy)) continue;
        final id = token.substring(legacy.length);
        if (id.isEmpty || (ids[store]?.hasMatch(id) ?? false)) {
          return '${store.prefix}$id';
        }
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
