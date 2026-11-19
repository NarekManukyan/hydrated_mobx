/// A [Storage] for hydrated_mobx that keeps each key in its own file and
/// nothing in memory until it is read. Not available on the web, so it is
/// imported on its own:
///
/// ```dart
/// import 'package:hydrated_mobx/file_storage.dart';
/// ```
library hydrated_mobx_file_storage;

import 'package:hydrated_mobx/hydrated_mobx.dart';

export 'src/file_storage.dart';
