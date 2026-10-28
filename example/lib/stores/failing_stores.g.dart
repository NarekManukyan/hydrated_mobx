// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'failing_stores.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$BrokenStore on BrokenStoreBase, Store {
  late final _$countAtom = Atom(
    name: 'BrokenStoreBase.count',
    context: context,
  );

  @override
  int get count {
    _$countAtom.reportRead();
    return super.count;
  }

  @override
  set count(int value) {
    _$countAtom.reportWrite(value, super.count, () {
      super.count = value;
    });
  }

  @override
  String toString() {
    return '''
count: ${count}
    ''';
  }
}

mixin _$UnencodableStore on UnencodableStoreBase, Store {
  late final _$payloadAtom = Atom(
    name: 'UnencodableStoreBase.payload',
    context: context,
  );

  @override
  Object get payload {
    _$payloadAtom.reportRead();
    return super.payload;
  }

  @override
  set payload(Object value) {
    _$payloadAtom.reportWrite(value, super.payload, () {
      super.payload = value;
    });
  }

  @override
  String toString() {
    return '''
payload: ${payload}
    ''';
  }
}

mixin _$ClosedStorageStore on ClosedStorageStoreBase, Store {
  late final _$countAtom = Atom(
    name: 'ClosedStorageStoreBase.count',
    context: context,
  );

  @override
  int get count {
    _$countAtom.reportRead();
    return super.count;
  }

  @override
  set count(int value) {
    _$countAtom.reportWrite(value, super.count, () {
      super.count = value;
    });
  }

  late final _$ClosedStorageStoreBaseActionController = ActionController(
    name: 'ClosedStorageStoreBase',
    context: context,
  );

  @override
  void increment() {
    final _$actionInfo = _$ClosedStorageStoreBaseActionController.startAction(
      name: 'ClosedStorageStoreBase.increment',
    );
    try {
      return super.increment();
    } finally {
      _$ClosedStorageStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
count: ${count}
    ''';
  }
}
