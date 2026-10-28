import 'package:hydrated_mobx/src/plain_json.dart';

/// Helpers for type-safe fromJson / toJson implementations to avoid manual
/// type checks and try/catch when reading from `Map<String, dynamic>`.
///
/// Example:
/// ```dart
/// @override
/// void fromJson(Map<String, dynamic> json) {
///   _meetings = HydratedJson.readList(
///     json,
///     'meetings',
///     MeetingDto.fromJson,
///   ).asObservable();
///   _meta = HydratedJson.readObject(json, 'meta', MetaDto.fromJson) ??
///       MetaDto(take: 20);
/// }
///
/// @override
/// Map<String, dynamic> toJson() => {
///   'meetings': HydratedJson.writeList(_meetings, (e) => e.toJson()),
///   'meta': _meta.toJson(),
/// };
/// ```
class HydratedJson {
  HydratedJson._();

  /// Reads a list from [json] under [key]. Returns an empty list if the key is
  /// missing, null, or not a [List]. Every element that is a [Map] (with any
  /// key type, as raw storage returns them) is passed to [fromJson] as a deep
  /// `Map<String, dynamic>`; other elements are skipped.
  static List<T> readList<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final value = json[key];
    if (value is! List) return <T>[];
    return [
      for (final item in value)
        if (item is Map) fromJson(_stringKeyed(item)),
    ];
  }

  /// Reads a single object from [json] under [key]. Returns null if the key is
  /// missing, the value is not a [Map], or [fromJson] returns null. A map with
  /// any key type is passed on as a deep `Map<String, dynamic>`.
  static T? readObject<T>(
    Map<String, dynamic> json,
    String key,
    T? Function(Map<String, dynamic>) fromJson,
  ) {
    final value = json[key];
    if (value is! Map) return null;
    return fromJson(_stringKeyed(value));
  }

  /// Reads a list of strings from [json] under [key], skipping elements that
  /// are not strings. Returns an empty list if the value is not a [List].
  static List<String> readStringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) return <String>[];
    return value.whereType<String>().toList();
  }

  /// Reads a [String] from [json] under [key].
  /// Returns [defaultValue] if missing or not a string.
  static String readString(
    Map<String, dynamic> json,
    String key, {
    String defaultValue = '',
  }) {
    final value = json[key];
    if (value is String) return value;
    return defaultValue;
  }

  /// Reads an [int] from [json] under [key].
  /// Returns [defaultValue] if missing or not an int.
  static int readInt(
    Map<String, dynamic> json,
    String key, {
    int defaultValue = 0,
  }) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return defaultValue;
  }

  /// Reads a [double] from [json] under [key].
  /// Returns [defaultValue] if missing or not a number.
  static double readDouble(
    Map<String, dynamic> json,
    String key, {
    double defaultValue = 0,
  }) {
    final value = json[key];
    if (value is num) return value.toDouble();
    return defaultValue;
  }

  /// Reads a [bool] from [json] under [key].
  /// Returns [defaultValue] if missing or not a bool.
  static bool readBool(
    Map<String, dynamic> json,
    String key, {
    bool defaultValue = false,
  }) {
    final value = json[key];
    if (value is bool) return value;
    return defaultValue;
  }

  /// Writes a list to a JSON-friendly list using [toJson] for each element.
  /// Handles observable and plain lists; null returns an empty list.
  static List<dynamic> writeList<T>(
    Iterable<T>? list,
    dynamic Function(T) toJson,
  ) {
    if (list == null) return <dynamic>[];
    return list.map<dynamic>(toJson).toList();
  }

  /// [map] as a deep `Map<String, dynamic>`. A map that already is one
  /// (as everything `fromJson` receives is) is used as it is.
  static Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> map) =>
      map is Map<String, dynamic>
          ? map
          : plainJson(map)! as Map<String, dynamic>;
}
