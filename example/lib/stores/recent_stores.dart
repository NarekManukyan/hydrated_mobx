import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';

import '../app/app_storages.dart';

part 'recent_stores.g.dart';

class RecentItemStore = RecentItemStoreBase with _$RecentItemStore;

/// One cached item per id (`recent_<id>`) in the capped recent box.
abstract class RecentItemStoreBase extends HydratedMobX with Store {
  RecentItemStoreBase(String storeId, Storage storage)
    : super(storeId: storeId, storage: storage);

  @observable
  int views = 0;

  @observable
  String? lastViewed;

  @action
  void view() {
    views++;
    lastViewed = DateTime.now().toIso8601String();
  }

  @override
  String get storagePrefix => kRecentPrefix;

  @override
  Map<String, dynamic>? toJson() => {'views': views, 'lastViewed': lastViewed};

  @override
  void fromJson(Map<String, dynamic> json) {
    views = HydratedJson.readInt(json, 'views');
    lastViewed = json['lastViewed'] as String?;
  }
}

class PinnedNoteStore = PinnedNoteStoreBase with _$PinnedNoteStore;

/// Shares the recent box but is never evicted: `evictable` only accepts
/// `recent_` keys.
abstract class PinnedNoteStoreBase extends HydratedMobX with Store {
  PinnedNoteStoreBase(Storage storage) : super(storage: storage);

  @observable
  String text = 'Pinned: never evicted';

  @override
  String get storagePrefix => 'pinned_note';

  @override
  Map<String, dynamic>? toJson() => {'text': text};

  @override
  void fromJson(Map<String, dynamic> json) {
    text = HydratedJson.readString(json, 'text', defaultValue: text);
  }
}
