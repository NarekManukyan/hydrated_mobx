import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'vault_note_store.g.dart';

class VaultNoteStore = VaultNoteStoreBase with _$VaultNoteStore;

/// A note kept in the AES-256 encrypted vault box.
abstract class VaultNoteStoreBase extends HydratedMobX with Store {
  VaultNoteStoreBase(Storage storage) : super(storage: storage);

  @observable
  String text = '';

  @action
  void setText(String value) => text = value;

  @override
  String get storagePrefix => 'vault_note';

  @override
  Map<String, dynamic>? toJson() => {'text': text};

  @override
  void fromJson(Map<String, dynamic> json) {
    text = HydratedJson.readString(json, 'text');
  }
}
