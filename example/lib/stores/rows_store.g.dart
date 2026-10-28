// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rows_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$RowsStore on RowsStoreBase, Store {
  late final _$revisionAtom = Atom(
    name: 'RowsStoreBase.revision',
    context: context,
  );

  @override
  int get revision {
    _$revisionAtom.reportRead();
    return super.revision;
  }

  @override
  set revision(int value) {
    _$revisionAtom.reportWrite(value, super.revision, () {
      super.revision = value;
    });
  }

  late final _$RowsStoreBaseActionController = ActionController(
    name: 'RowsStoreBase',
    context: context,
  );

  @override
  void bump() {
    final _$actionInfo = _$RowsStoreBaseActionController.startAction(
      name: 'RowsStoreBase.bump',
    );
    try {
      return super.bump();
    } finally {
      _$RowsStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
revision: ${revision}
    ''';
  }
}
