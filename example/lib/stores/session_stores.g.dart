// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_stores.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$CartStore on CartStoreBase, Store {
  late final _$itemsAtom = Atom(name: 'CartStoreBase.items', context: context);

  @override
  ObservableList<String> get items {
    _$itemsAtom.reportRead();
    return super.items;
  }

  @override
  set items(ObservableList<String> value) {
    _$itemsAtom.reportWrite(value, super.items, () {
      super.items = value;
    });
  }

  late final _$CartStoreBaseActionController = ActionController(
    name: 'CartStoreBase',
    context: context,
  );

  @override
  void add(String item) {
    final _$actionInfo = _$CartStoreBaseActionController.startAction(
      name: 'CartStoreBase.add',
    );
    try {
      return super.add(item);
    } finally {
      _$CartStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
items: ${items}
    ''';
  }
}

mixin _$DraftStore on DraftStoreBase, Store {
  late final _$textAtom = Atom(name: 'DraftStoreBase.text', context: context);

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

  late final _$DraftStoreBaseActionController = ActionController(
    name: 'DraftStoreBase',
    context: context,
  );

  @override
  void setText(String value) {
    final _$actionInfo = _$DraftStoreBaseActionController.startAction(
      name: 'DraftStoreBase.setText',
    );
    try {
      return super.setText(value);
    } finally {
      _$DraftStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
text: ${text}
    ''';
  }
}

mixin _$AccountPrefsStore on AccountPrefsStoreBase, Store {
  late final _$visitsAtom = Atom(
    name: 'AccountPrefsStoreBase.visits',
    context: context,
  );

  @override
  int get visits {
    _$visitsAtom.reportRead();
    return super.visits;
  }

  @override
  set visits(int value) {
    _$visitsAtom.reportWrite(value, super.visits, () {
      super.visits = value;
    });
  }

  late final _$compactModeAtom = Atom(
    name: 'AccountPrefsStoreBase.compactMode',
    context: context,
  );

  @override
  bool get compactMode {
    _$compactModeAtom.reportRead();
    return super.compactMode;
  }

  @override
  set compactMode(bool value) {
    _$compactModeAtom.reportWrite(value, super.compactMode, () {
      super.compactMode = value;
    });
  }

  late final _$AccountPrefsStoreBaseActionController = ActionController(
    name: 'AccountPrefsStoreBase',
    context: context,
  );

  @override
  void countVisit() {
    final _$actionInfo = _$AccountPrefsStoreBaseActionController.startAction(
      name: 'AccountPrefsStoreBase.countVisit',
    );
    try {
      return super.countVisit();
    } finally {
      _$AccountPrefsStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  void toggleCompact() {
    final _$actionInfo = _$AccountPrefsStoreBaseActionController.startAction(
      name: 'AccountPrefsStoreBase.toggleCompact',
    );
    try {
      return super.toggleCompact();
    } finally {
      _$AccountPrefsStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
visits: ${visits},
compactMode: ${compactMode}
    ''';
  }
}
