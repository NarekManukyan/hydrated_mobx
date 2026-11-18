import 'dart:convert';
import 'dart:typed_data';

import 'package:hydrated_mobx/src/gzip/gzip.dart';

/// How a `HydratedStorage` keeps state in its box, and so in memory: Hive
/// holds every value of an open box in RAM for as long as it is open.
enum HydratedEncoding {
  /// As Hive's own maps and lists. Reads cost nothing, but a decoded JSON
  /// tree takes about 5 times the memory of its UTF-8 text.
  tree,

  /// As UTF-8 JSON bytes, decoded on each read: about a fifth of the memory
  /// of [tree].
  json,

  /// As gzipped UTF-8 JSON bytes, decoded on each read: typically a few
  /// percent of the memory of [tree]. Not available on the web.
  gzipJson,
}

/// Starts every encoded value. `0x89` is not valid UTF-8 or JSON, so plain
/// bytes an app stores itself are unlikely to begin with it.
const _magic = [0x89, 0x48, 0x4d]; // 0x89 'H' 'M'
const _jsonFormat = 1;
const _gzipFormat = 2;
const _headerLength = 4;

/// Turns state into what the box keeps, and back. Internal.
class HydratedValueCodec {
  /// Encodes maps and lists whose JSON is at least [encodeAbove] bytes long
  /// as [encoding] says.
  const HydratedValueCodec(this.encoding, {this.encodeAbove = 0});

  /// How large state is kept.
  final HydratedEncoding encoding;

  /// Size of UTF-8 JSON below which state stays a tree.
  final int encodeAbove;

  /// The form [value] is kept in: itself, or its encoded bytes.
  Object? encode(Object? value) {
    // Bytes are lists too, but already as compact as they get.
    if (encoding == HydratedEncoding.tree ||
        value is TypedData ||
        (value is! Map && value is! List)) {
      return value;
    }
    final List<int> bytes;
    try {
      bytes = utf8.encode(jsonEncode(value));
      // Thrown for values JSON cannot hold, which is not a bug here.
      // ignore: avoid_catching_errors
    } on JsonUnsupportedObjectError {
      return value; // Not plain JSON, e.g. imported data: Hive keeps it.
    }
    if (bytes.length < encodeAbove) return value;
    final gzipped = encoding == HydratedEncoding.gzipJson;
    final body = gzipped ? gzipEncode(bytes) : bytes;
    return Uint8List(_headerLength + body.length)
      ..setAll(0, _magic)
      ..[3] = gzipped ? _gzipFormat : _jsonFormat
      ..setAll(_headerLength, body);
  }

  /// [stored] decoded when it is an encoded value, otherwise as it is, so
  /// values written before an encoding was chosen still read.
  static Object? decode(Object? stored) {
    if (!isEncoded(stored)) return stored;
    final bytes = stored! as Uint8List;
    final body = Uint8List.sublistView(bytes, _headerLength);
    final text = bytes[3] == _gzipFormat ? gzipDecode(body) : body;
    return jsonDecode(utf8.decode(text));
  }

  /// Whether [stored] is a value [encode] produced.
  static bool isEncoded(Object? stored) =>
      stored is Uint8List &&
      stored.length >= _headerLength &&
      stored[0] == _magic[0] &&
      stored[1] == _magic[1] &&
      stored[2] == _magic[2] &&
      (stored[3] == _jsonFormat || stored[3] == _gzipFormat);
}
