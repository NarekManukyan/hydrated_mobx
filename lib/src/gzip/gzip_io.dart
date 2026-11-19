import 'dart:io';

/// Whether this platform can gzip.
const gzipSupported = true;

/// Compresses [bytes] with gzip.
List<int> gzipEncode(List<int> bytes) => gzip.encode(bytes);

/// Decompresses gzip [bytes].
List<int> gzipDecode(List<int> bytes) => gzip.decode(bytes);
