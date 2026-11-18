import 'dart:convert';
import 'dart:typed_data';

import 'package:hydrated_mobx/src/gzip/gzip.dart';
import 'package:meta/meta.dart';

/// How a storage keeps state.
///
/// For a `HydratedStorage`, how state is kept in its box, and so in memory:
/// Hive holds every value of an open box in RAM for as long as it is open.
/// For a `FileStorage`, how state is written to its files: [json] or
/// [gzipJson], since a file holds bytes.
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

/// Bytes kept as they are, which only [HydratedValueCodec.file] writes.
const _bytesFormat = 0;
const _jsonFormat = 1;
const _gzipFormat = 2;
const _headerLength = 4;

/// Writes UTF-8 JSON straight to bytes, without a `String` in between.
final _toUtf8Json = JsonUtf8Encoder();

/// Reads UTF-8 JSON straight from bytes; the fused decoder skips the
/// intermediate `String`.
final _fromUtf8Json = utf8.decoder.fuse(json.decoder);

/// Turns state into what a storage keeps, and back.
@internal
class HydratedValueCodec {
  /// For a box: encodes maps and lists whose JSON is longer than
  /// [encodeAbove] bytes as [encoding] says, and keeps every other value as
  /// it is.
  const HydratedValueCodec(this.encoding, {this.encodeAbove = 0})
      : _everyValue = false;

  /// For a file, which holds bytes: encodes every value, as [encoding] says
  /// ([HydratedEncoding.json] or [HydratedEncoding.gzipJson]), and bytes as
  /// they are.
  const HydratedValueCodec.file(this.encoding)
      : encodeAbove = 0,
        _everyValue = true;

  /// How state is kept.
  final HydratedEncoding encoding;

  /// Size of UTF-8 JSON up to which a box keeps state as a tree.
  final int encodeAbove;

  final bool _everyValue;

  /// The form [value] is kept in: itself, or its encoded bytes.
  ///
  /// For a file, throws [JsonUnsupportedObjectError] for a value JSON cannot
  /// hold, failing the write.
  Object? encode(Object? value) {
    if (_everyValue) {
      if (value is Uint8List) return _framed(_bytesFormat, value);
      return _encodeJson(_toUtf8Json.convert(value));
    }
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
    return _encodeJson(bytes);
  }

  Uint8List _encodeJson(List<int> bytes) =>
      encoding == HydratedEncoding.gzipJson
          ? _framed(_gzipFormat, gzipEncode(bytes))
          : _framed(_jsonFormat, bytes);

  static Uint8List _framed(int format, List<int> body) =>
      Uint8List(_headerLength + body.length)
        ..setAll(0, _magic)
        ..[3] = format
        ..setAll(_headerLength, body);

  /// [stored] decoded when it is an encoded value. Any other value is, for a
  /// box, returned as it is, so values written before an encoding was chosen
  /// still read, and for a file a [FormatException].
  Object? decode(Object? stored) {
    final format = _formatOf(stored);
    if (format == null) {
      if (_everyValue) {
        throw const FormatException('Not a hydrated_mobx value file');
      }
      return stored;
    }
    final body = Uint8List.sublistView(stored! as Uint8List, _headerLength);
    return switch (format) {
      _bytesFormat => Uint8List.fromList(body),
      _gzipFormat => _fromUtf8Json.convert(gzipDecode(body)),
      _ => _fromUtf8Json.convert(body),
    };
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
  int? _formatOf(Object? stored) {
    if (stored is! Uint8List ||
        stored.length < _headerLength ||
        stored[0] != _magic[0] ||
        stored[1] != _magic[1] ||
        stored[2] != _magic[2]) {
      return null;
    }
    return switch (stored[3]) {
      _jsonFormat || _gzipFormat => stored[3],
      _bytesFormat when _everyValue => _bytesFormat,
      _ => null,
    };
  }
}
