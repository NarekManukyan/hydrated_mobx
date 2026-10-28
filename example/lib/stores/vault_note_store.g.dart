// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_note_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$VaultNoteStore on VaultNoteStoreBase, Store {
  late final _$textAtom =
      Atom(name: 'VaultNoteStoreBase.text', context: context);

  @override
  String get text {
    _$textAtom.reportRead();
    return super.text;
  }

  @override
  set text(String value) {
    _$textAtom.reportWrite(value, super.text, () {
      super.text = value;
    });
  }

  late final _$VaultNoteStoreBaseActionController =
      ActionController(name: 'VaultNoteStoreBase', context: context);

  @override
  void setText(String value) {
    final _$actionInfo = _$VaultNoteStoreBaseActionController.startAction(
        name: 'VaultNoteStoreBase.setText');
    try {
      return super.setText(value);
    } finally {
      _$VaultNoteStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
text: ${text}
    ''';
  }
}
