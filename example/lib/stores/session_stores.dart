import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

import '../app/app_storages.dart';

part 'session_stores.g.dart';

const kDraftPrefix = 'draft_';

class CartStore = CartStoreBase with _$CartStore;

/// Lives in the session box: gone after sign-out.
abstract class CartStoreBase extends HydratedMobX with Store {
  CartStoreBase() : super(storage: appStorages.session);

  @observable
  ObservableList<String> items = ObservableList();

  @action
  void add(String item) => items.add(item);

  @override
  String get storagePrefix => 'cart';

  @override
  Map<String, dynamic>? toJson() => {'items': items.toList()};

  @override
  void fromJson(Map<String, dynamic> json) {
    items = ObservableList.of(HydratedJson.readStringList(json, 'items'));
  }
}

class DraftStore = DraftStoreBase with _$DraftStore;

/// A message draft, also in the session box, under a `draft_` key so it can
/// be cleared on its own.
abstract class DraftStoreBase extends HydratedMobX with Store {
  DraftStoreBase() : super(storage: appStorages.session, storeId: 'compose');

  @observable
  String text = '';

  @action
  void setText(String value) => text = value;

  @override
  String get storagePrefix => kDraftPrefix;

  @override
  Map<String, dynamic>? toJson() => {'text': text};

  @override
  void fromJson(Map<String, dynamic> json) {
    text = HydratedJson.readString(json, 'text');
  }
}

class AccountPrefsStore = AccountPrefsStoreBase with _$AccountPrefsStore;

/// Lives in the account box: survives sign-out.
abstract class AccountPrefsStoreBase extends HydratedMobX with Store {
  AccountPrefsStoreBase() : super(storage: appStorages.account);

  @observable
  int visits = 0;

  @observable
  bool compactMode = false;

  @action
  void countVisit() => visits++;

  @action
  void toggleCompact() => compactMode = !compactMode;

  @override
  String get storagePrefix => 'account_prefs';

  @override
  Map<String, dynamic>? toJson() => {
        'visits': visits,
        'compactMode': compactMode,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    visits = HydratedJson.readInt(json, 'visits');
    compactMode = HydratedJson.readBool(json, 'compactMode');
  }
}
