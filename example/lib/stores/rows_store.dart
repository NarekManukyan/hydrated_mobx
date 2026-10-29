import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'rows_store.g.dart';

class RowsStore = RowsStoreBase with _$RowsStore;

/// A large state of plain JSON rows, written with or without the
/// traversal [trustToJson] skips.
abstract class RowsStoreBase extends HydratedMobX with Store {
  RowsStoreBase({required this.trusted, required int rowCount, super.storage})
    : _rows = [
        for (var i = 0; i < rowCount; i++)
          {
            'id': i,
            'title': 'Row $i',
            'score': 0,
            'tags': ['a', 'b'],
          },
      ];

  final bool trusted;
  final List<Map<String, dynamic>> _rows;

  /// Bumped by every change, so the persistence reaction re-runs.
  @observable
  int revision = 0;

  @action
  void bump() {
    final row = _rows[revision % _rows.length];
    row['score'] = (row['score'] as int) + 1;
    revision++;
  }

  @override
  String get storagePrefix => trusted ? 'rows_trusted' : 'rows_traversed';

  @override
  bool get trustToJson => trusted;

  // Fresh maps and lists on every call, as trustToJson requires.
  @override
  Map<String, dynamic>? toJson() => {
    'revision': revision,
    'rows': [
      for (final row in _rows)
        {
          ...row,
          'tags': [...row['tags'] as List],
        },
    ],
  };

  @override
  void fromJson(Map<String, dynamic> json) {
    revision = HydratedJson.readInt(json, 'revision');
  }
}
