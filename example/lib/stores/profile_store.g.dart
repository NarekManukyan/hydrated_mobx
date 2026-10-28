// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ProfileStore on ProfileStoreBase, Store {
  late final _$displayNameAtom =
      Atom(name: 'ProfileStoreBase.displayName', context: context);

  @override
  String get displayName {
    _$displayNameAtom.reportRead();
    return super.displayName;
  }

  @override
  set displayName(String value) {
    _$displayNameAtom.reportWrite(value, super.displayName, () {
      super.displayName = value;
    });
  }

  late final _$bioAtom = Atom(name: 'ProfileStoreBase.bio', context: context);

  @override
  String get bio {
    _$bioAtom.reportRead();
    return super.bio;
  }

  @override
  set bio(String value) {
    _$bioAtom.reportWrite(value, super.bio, () {
      super.bio = value;
    });
  }

  late final _$ProfileStoreBaseActionController =
      ActionController(name: 'ProfileStoreBase', context: context);

  @override
  void update({String? displayName, String? bio}) {
    final _$actionInfo = _$ProfileStoreBaseActionController.startAction(
        name: 'ProfileStoreBase.update');
    try {
      return super.update(displayName: displayName, bio: bio);
    } finally {
      _$ProfileStoreBaseActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
displayName: ${displayName},
bio: ${bio}
    ''';
  }
}
