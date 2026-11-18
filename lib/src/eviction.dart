import 'package:hydrated_mobx/src/hydrated_mobx.dart';
import 'package:meta/meta.dart';

/// Throws for `evict` arguments no storage accepts.
@internal
void checkEvictArguments({Duration? olderThan, int? maxEntries}) {
  if (maxEntries != null && maxEntries < 0) {
    throw ArgumentError.value(maxEntries, 'maxEntries', 'must be >= 0');
  }
  if (olderThan != null && olderThan.isNegative) {
    throw ArgumentError.value(olderThan, 'olderThan', 'must not be negative');
  }
}

/// The state keys among [keys] that `evict` deletes, given each one's
/// [usedAt] (ms since epoch) and the time [now]: those not used for
/// [olderThan], then all but the [maxEntries] most recently used of the
/// rest. Version keys, keys [where] rejects and keys in [live] are never
/// chosen and do not count towards [maxEntries]. [live] is read after
/// [where] has run, which may itself have created a store.
@internal
Set<String> evictionsAmong(
  Iterable<String> keys, {
  required int Function(String key) usedAt,
  required int now,
  Duration? olderThan,
  int? maxEntries,
  bool Function(String key)? where,
  Set<String> Function()? live,
}) {
  final accepted = [
    for (final key in keys)
      if (!HydratedMobX.isVersionKey(key) && (where?.call(key) ?? true)) key,
  ];
  final spared = live?.call() ?? const <String>{};
  final candidates = [
    for (final key in accepted)
      if (!spared.contains(key)) (key: key, usedAt: usedAt(key)),
  ];
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
  return doomed;
}
