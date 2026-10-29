import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

part 'profile_store.g.dart';

const kProfileToken = 'profile';

class ProfileStore = ProfileStoreBase with _$ProfileStore;

/// Schema history:
/// - v1 `{'user': 'Ann Lee'}`: too old to read, dropped.
/// - v2 `{'name': 'Ann', 'bio': ...}`: `name` renamed to `displayName`.
/// - v3 `{'displayName': 'Ann', 'bio': ...}`: current.
abstract class ProfileStoreBase extends HydratedMobX with Store {
  ProfileStoreBase();

  @observable
  String displayName = '';

  @observable
  String bio = '';

  @override
  String get storagePrefix => kProfileToken;

  @override
  int get version => 3;

  @override
  Map<String, dynamic>? migrate(int oldVersion, Map<String, dynamic> oldState) {
    if (oldVersion < 2) return null;
    if (oldVersion < 3) oldState['displayName'] = oldState.remove('name');
    return oldState;
  }

  @override
  Map<String, dynamic>? toJson() => {'displayName': displayName, 'bio': bio};

  @override
  void fromJson(Map<String, dynamic> json) {
    displayName = HydratedJson.readString(json, 'displayName');
    bio = HydratedJson.readString(json, 'bio');
  }
}
