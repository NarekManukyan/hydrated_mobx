import 'package:meta/meta.dart';

/// A fresh, deep copy of [value] in which every map is `Map<String, dynamic>`
/// and every list is `List<dynamic>`, whatever types the storage returned.
@internal
Object? plainJson(Object? value) => switch (value) {
      Map() => <String, dynamic>{
          for (final MapEntry(:key, :value) in value.entries)
            '$key': plainJson(value),
        },
      List() => <dynamic>[for (final item in value) plainJson(item)],
      _ => value,
    };
