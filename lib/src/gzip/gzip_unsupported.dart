/// Whether this platform can gzip.
const gzipSupported = false;

/// Compresses [bytes] with gzip.
List<int> gzipEncode(List<int> bytes) =>
    throw UnsupportedError('gzip is not available on this platform');

/// Decompresses gzip [bytes].
List<int> gzipDecode(List<int> bytes) =>
    throw UnsupportedError('gzip is not available on this platform');
