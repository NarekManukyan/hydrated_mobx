import 'dart:convert';
import 'dart:typed_data';

import 'package:hydrated_mobx/src/gzip/gzip.dart';
import 'package:meta/meta.dart';

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

/// Starts every encoded value, followed by a format byte. `0x89` alone is
/// not rare (every PNG starts with it), so a value counts as encoded only
/// when it starts with all three magic bytes and a known format byte.
const _magic = [0x89, 0x48, 0x4d]; // 0x89 'H' 'M'
const _jsonFormat = 1;
const _gzipFormat = 2;
const _headerLength = 4;

/// Writes UTF-8 JSON straight to bytes, without a `String` in between.
final _toUtf8Json = JsonUtf8Encoder();

/// Reads UTF-8 JSON straight from bytes; the fused decoder skips the
/// intermediate `String`.
final _fromUtf8Json = utf8.decoder.fuse(json.decoder);

/// Turns state into what the box keeps, and back.
@internal
class HydratedValueCodec {
  /// Encodes maps and lists whose JSON is longer than [encodeAbove] bytes
  /// as [encoding] says.
  const HydratedValueCodec(this.encoding, {this.encodeAbove = 0});

  /// How large state is kept.
  final HydratedEncoding encoding;

  /// Size of UTF-8 JSON up to which state stays a tree.
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
      bytes = _toUtf8Json.convert(value);
      // Thrown for values JSON cannot hold, which is not a bug here.
      // ignore: avoid_catching_errors
    } on JsonUnsupportedObjectError {
      return value; // Not plain JSON, e.g. imported data: Hive keeps it.
    }
    if (bytes.length <= encodeAbove) return value;
    final gzipped = encoding == HydratedEncoding.gzipJson;
    final body = gzipped ? gzipEncode(bytes) : bytes;
    return Uint8List(_headerLength + body.length)
      ..setAll(0, _magic)
      ..[3] = gzipped ? _gzipFormat : _jsonFormat
      ..setAll(_headerLength, body);
  }

  /// [stored] decoded when it is an encoded value, otherwise as it is, so
  /// values written before an encoding was chosen still read.
  Object? decode(Object? stored) {
    final format = _formatOf(stored);
    if (format == null) return stored;
    final body = Uint8List.sublistView(stored! as Uint8List, _headerLength);
    return _fromUtf8Json
        .convert(format == _gzipFormat ? gzipDecode(body) : body);
  }

  /// [stored] in the form [encode] gives the value it decodes to, or
  /// [stored] itself when it already has that form, which the caller can
  /// tell by identity.
  Object? reencode(Object? stored) {
    final format = _formatOf(stored);
    final state = decode(stored);
    final wanted = encode(state);
    if (identical(wanted, state)) return format == null ? stored : state;
    return format == (wanted! as Uint8List)[3] ? stored : wanted;
  }

  /// The format byte of an encoded value, or `null` for any other value.
  static int? _formatOf(Object? stored) {
    if (stored is! Uint8List ||
        stored.length < _headerLength ||
        stored[0] != _magic[0] ||
        stored[1] != _magic[1] ||
        stored[2] != _magic[2]) {
      return null;
    }
    final format = stored[3];
    return format == _jsonFormat || format == _gzipFormat ? format : null;
  }
}
