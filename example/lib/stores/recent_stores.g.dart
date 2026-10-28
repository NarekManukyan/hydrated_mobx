// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recent_stores.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$RecentItemStore on RecentItemStoreBase, Store {
  late final _$viewsAtom = Atom(
    name: 'RecentItemStoreBase.views',
    context: context,
  );

  @override
  int get views {
    _$viewsAtom.reportRead();
    return super.views;
  }

  @override
  set views(int value) {
    _$viewsAtom.reportWrite(value, super.views, () {
      super.views = value;
    });
  }

  late final _$lastViewedAtom = Atom(
    name: 'RecentItemStoreBase.lastViewed',
    context: context,
  );

  @override
  String? get lastViewed {
    _$lastViewedAtom.reportRead();
    return super.lastViewed;
  }

  @override
  set lastViewed(String? value) {
    _$lastViewedAtom.reportWrite(value, super.lastViewed, () {
      super.lastViewed = value;
    });
  }

  late final _$RecentItemStoreBaseActionController = ActionController(
    name: 'RecentItemStoreBase',
    context: context,
  );

  @override
  void view() {
    final _$actionInfo = _$RecentItemStoreBaseActionController.startAction(
      name: 'RecentItemStoreBase.view',
    );
    try {
      return super.view();
    } finally {
      _$RecentItemStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
views: ${views},
lastViewed: ${lastViewed}
    ''';
  }
}

mixin _$PinnedNoteStore on PinnedNoteStoreBase, Store {
  late final _$textAtom = Atom(
    name: 'PinnedNoteStoreBase.text',
    context: context,
  );

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

  @override
  String toString() {
    return '''
text: ${text}
    ''';
  }
}
