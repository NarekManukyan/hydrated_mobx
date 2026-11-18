import 'package:hydrated_mobx/src/hydrated_mobx.dart';
import 'package:meta/meta.dart';

/// Throws for `evict` arguments no storage accepts. [olderThanName] names
/// [olderThan] in the error, for a caller that calls it something else.
@internal
void checkEvictArguments({
  Duration? olderThan,
  int? maxEntries,
  String olderThanName = 'olderThan',
}) {
  if (maxEntries != null && maxEntries < 0) {
    throw ArgumentError.value(maxEntries, 'maxEntries', 'must be >= 0');
  }
  if (olderThan != null && olderThan.isNegative) {
    throw ArgumentError.value(olderThan, olderThanName, 'must not be negative');
  }
}

/// [time] (ms since epoch) as a use time: never after [now], since a time
/// in the future would rank its key above every use to come, and keep
/// [isUseDue] from recording one until then.
@internal
int useTimeAt(int time, int now) => time < now ? time : now;

/// Whether the use time of [key], last recorded at [last] (ms since epoch,
/// `null` if never), is due to be rewritten at [now]: it is a state key and
/// was not recorded within [resolution].
@internal
bool isUseDue(
  String key, {
  required int? last,
  required int now,
  required Duration resolution,
}) =>
    !HydratedMobX.isVersionKey(key) &&
    (last == null || now - last >= resolution.inMilliseconds);

/// The state keys among [keys] that `evict` deletes, given each one's
/// [usedAt] (ms since epoch) and the time [now]: those not used for
/// [olderThan], then all but the [maxEntries] most recently used of the
/// rest. Version keys, keys [where] rejects, keys in [live] and keys [gone]
/// reports are never chosen and do not count towards [maxEntries]. [live]
/// and [gone] are read after [where] has run, which may itself have created
/// a store or queued a delete.
@internal
Set<String> evictionsAmong(
  Iterable<String> keys, {
  required int Function(String key) usedAt,
  required int now,
  Duration? olderThan,
  int? maxEntries,
  bool Function(String key)? where,
  Set<String> Function()? live,
  bool Function(String key)? gone,
}) {
  final accepted = [
    for (final key in keys)
      if (!HydratedMobX.isVersionKey(key) && (where?.call(key) ?? true)) key,
  ];
  final spared = live?.call() ?? const <String>{};
  final candidates = [
    for (final key in accepted)
      if (!spared.contains(key) && !(gone?.call(key) ?? false))
        (key: key, usedAt: usedAt(key)),
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
