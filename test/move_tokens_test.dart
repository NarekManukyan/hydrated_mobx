import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:test/test.dart';

class _Counter extends HydratedMobX with Store {
  _Counter({super.storage, super.storeId});

  int count = 0;

  @override
  String get storagePrefix => 'counter';

  @override
  Map<String, dynamic>? toJson() => {'count': count};

  @override
  void fromJson(Map<String, dynamic> json) => count = json['count'] as int;
}

const _id = '0123456789abcdef0123456789abcdef';
const _letterId = 'abcdef0123456789abcdef0123456789';

void main() {
  group('moveTokens', () {
    test('moves state with its version key and returns the moves', () async {
      final storage = InMemoryStorage({
        'Old': {'count': 1},
        'Old.__version': 3,
        'keep': {'count': 2},
      });

      final moved = await HydratedMobX.moveTokens(
        (token, _) => token == 'Old' ? 'new' : null,
        storage: storage,
      );

      expect(moved, {'Old': 'new'});
      expect(storage.keys.toSet(), {'new', 'new.__version', 'keep'});
      expect(storage.read('new'), {'count': 1});
      expect(storage.read('new.__version'), 3);
    });

    test('never overwrites different state', () async {
      final storage = InMemoryStorage({
        'old': {'count': 1},
        'new': {'count': 2},
      });

      final moved = await HydratedMobX.moveTokens(
        (token, _) => token == 'old' ? 'new' : null,
        storage: storage,
      );

      expect(moved, isEmpty);
      expect(storage.read('old'), {'count': 1});
      expect(storage.read('new'), {'count': 2});
    });

    test('finishes a move interrupted before the old key was deleted',
        () async {
      final storage = InMemoryStorage({
        'old': {'count': 1},
        'old.__version': 2,
        'new': {'count': 1},
        'new.__version': 2,
      });

      final moved = await HydratedMobX.moveTokens(
        (token, _) => token == 'old' ? 'new' : null,
        storage: storage,
      );

      expect(moved, {'old': 'new'});
      expect(storage.keys.toSet(), {'new', 'new.__version'});
    });

    test('drops a stale version key of the new token', () async {
      final storage = InMemoryStorage({
        'old': {'count': 1},
        'new.__version': 5,
      });

      await HydratedMobX.moveTokens(
        (token, _) => token == 'old' ? 'new' : null,
        storage: storage,
      );

      expect(storage.keys.toSet(), {'new'});
    });

    test('skips keys that would move to the same token', () async {
      final storage = InMemoryStorage({
        'a': {'count': 1},
        'b': {'count': 2},
      });

      final moved = await HydratedMobX.moveTokens(
        (_, __) => 'new',
        storage: storage,
      );

      expect(moved, isEmpty);
      expect(storage.keys.toSet(), {'a', 'b'});
    });

    test('skips tokens of live stores', () async {
      final storage = InMemoryStorage({
        'old': {'count': 1},
        'legacy': {'count': 2},
      });
      final store = _Counter(storage: storage, storeId: 'x');
      addTearDown(store.dispose);

      final moved = await HydratedMobX.moveTokens(
        (token, _) => token == 'old' ? 'counterx' : 'other',
        storage: storage,
      );

      expect(moved, {'legacy': 'other'});
      expect(storage.read('old'), {'count': 1});
    });

    test('rejects a version key as the new token', () {
      final storage = InMemoryStorage({'old': 1});

      expect(
        () => HydratedMobX.moveTokens(
          (_, __) => 'new.__version',
          storage: storage,
        ),
        throwsArgumentError,
      );
    });
  });

  group('LegacyTokens.match', () {
    const user = LegacyStore(
      prefix: 'user',
      legacyPrefix: 'UserStore',
      keys: ['currentUser', 'settings'],
    );
    final chat = LegacyStore(
      prefix: 'chat_',
      legacyPrefix: 'ChatStore',
      keys: const ['messages'],
      idPattern: RegExp('[0-9a-f]{32}'),
    );
    const tags = LegacyStore(
      prefix: 'tags',
      legacyPrefix: 'TagsStore',
      keys: ['tags', 'count'],
      requiredKeys: ['tags', 'count'],
    );
    final to = LegacyTokens.match([user, chat, tags], reservedPrefixes: ['n_']);

    test('finds keys by their 1.x type name', () {
      expect(to('UserStore', {'currentUser': 1}), 'user');
      expect(to('ChatStore$_id', {'messages': <Object>[]}), 'chat_$_id');
    });

    test('finds obfuscated keys by the shape of their state', () {
      expect(to('aB', {'currentUser': 1, 'settings': 2}), 'user');
      expect(to(r'x$', {'messages': <Object>[]}), 'chat_');
      expect(to('Qz$_id', {'messages': <Object>[]}), 'chat_$_id');
      expect(to('Qz$_letterId', {'messages': <Object>[]}), 'chat_$_letterId');
    });

    test('a type name now given to another class does not move state', () {
      expect(to('UserStore', {'messages': <Object>[]}), 'chat_');
      expect(to('UserStore', {'unknown': 1}), isNull);
    });

    test('requires the shape to fit exactly one store', () {
      final ambiguous = LegacyTokens.match([
        user,
        const LegacyStore(prefix: 'profile', keys: ['currentUser']),
      ]);

      expect(ambiguous('aB', {'currentUser': 1}), isNull);
      expect(to('aB', {'currentUser': 1, 'extra': 2}), isNull);
      expect(to('aB', {'settings': 2}), isNull);
      expect(to('aB', {'tags': <Object>[]}), isNull);
      expect(to('aB', {'tags': <Object>[], 'count': 0}), 'tags');
    });

    test('leaves current and reserved prefixes, and non-type keys, alone', () {
      expect(to('user', {'currentUser': 1}), isNull);
      expect(to('chat_$_id', {'messages': <Object>[]}), isNull);
      expect(to('n_1', {'currentUser': 1}), isNull);
      expect(to('some.key', {'currentUser': 1}), isNull);
      expect(to('Qz-not-an-id', {'messages': <Object>[]}), isNull);
    });

    test('drives moveTokens', () async {
      final storage = InMemoryStorage({
        'aB': {'currentUser': 1},
        'Qz$_id': {'messages': <Object>[]},
        'Qz$_id.__version': 2,
        'n_cache': {'currentUser': 1},
      });

      final moved = await HydratedMobX.moveTokens(to, storage: storage);

      expect(moved, {'aB': 'user', 'Qz$_id': 'chat_$_id'});
      expect(
        storage.keys.toSet(),
        {'user', 'chat_$_id', 'chat_$_id.__version', 'n_cache'},
      );
    });
  });
}
