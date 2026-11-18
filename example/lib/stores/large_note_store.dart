import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

/// The token prefix of every large note.
const kLargeNotePrefix = 'doc_';

/// A note with a long transcript, one key per note (`doc_<id>`). Written
/// without codegen: an [Observable] read through a getter.
class LargeNoteStore extends HydratedMobX with Store {
  LargeNoteStore(String id, Storage storage)
    : super(storeId: id, storage: storage);

  final _lines = Observable(<String>[]);

  List<String> get lines => _lines.value;

  /// Fills the transcript with [count] lines.
  void write(int count) => runInAction(
    () => _lines.value = [
      for (var i = 0; i < count; i++)
        'Speaker ${i % 3}: line $i of the meeting transcript, '
            'with enough words to make the state realistically large.',
    ],
  );

  @override
  String get storagePrefix => kLargeNotePrefix;

  @override
  Map<String, dynamic>? toJson() => {'lines': lines};

  @override
  void fromJson(Map<String, dynamic> json) =>
      _lines.value = HydratedJson.readStringList(json, 'lines');
}
