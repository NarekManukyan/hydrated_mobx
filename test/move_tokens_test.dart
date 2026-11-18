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

/// Calls a `to` for [HydratedMobX.moveTokens] with [value] as the stored
/// value.
String? _at(
  String? Function(String token, Object? Function() value) to,
  String token,
  Object? value,
) =>
    to(token, () => value);

class _CountingStorage extends ForwardingStorage {
  _CountingStorage(super.inner);

  final reads = <String>[];

  @override
  dynamic read(String key) {
    reads.add(key);
    return super.read(key);
  }
}

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

    test('reads only the values to asks for', () async {
      final storage = _CountingStorage(
        InMemoryStorage({
          'old': {'count': 1},
          'other': {'count': 2},
        }),
      );

      final moved = await HydratedMobX.moveTokens(
        (token, value) =>
            token == 'old' && value() is Map && value() != null ? 'new' : null,
        storage: storage,
      );

      expect(moved, {'old': 'new'});
      // Once for to, however often it asks, and once for the move.
      expect(storage.reads.where((key) => key == 'old'), hasLength(2));
      expect(storage.reads, isNot(contains('other')));
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
      fields: ['currentUser', 'settings'],
    );
    final chat = LegacyStore(
      prefix: 'chat_',
      legacyPrefix: 'ChatStore',
      fields: const ['messages'],
      idPattern: RegExp('[0-9a-f]{32}'),
    );
    const tags = LegacyStore(
      prefix: 'tags',
      legacyPrefix: 'TagsStore',
      fields: ['tags', 'count'],
      requiredFields: ['tags', 'count'],
    );
    final to = LegacyTokens.match([user, chat, tags], reservedPrefixes: ['n_']);

    test('finds keys by their 1.x type name', () {
      expect(_at(to, 'UserStore', {'currentUser': 1}), 'user');
      expect(_at(to, 'ChatStore$_id', {'messages': <Object>[]}), 'chat_$_id');
    });

    test('finds obfuscated keys by the shape of their state', () {
      expect(_at(to, 'aB', {'currentUser': 1, 'settings': 2}), 'user');
      expect(_at(to, r'x$', {'messages': <Object>[]}), 'chat_');
      expect(_at(to, 'Qz$_id', {'messages': <Object>[]}), 'chat_$_id');
      expect(
        _at(to, 'Qz$_letterId', {'messages': <Object>[]}),
        'chat_$_letterId',
      );
    });

    test('a short obfuscated name keeps a keyed id whole', () {
      final short = LegacyTokens.match([
        LegacyStore(
          prefix: 'chat_',
          legacyPrefix: 'a',
          fields: const ['messages'],
          idPattern: RegExp('[0-9a-f]{32}'),
        ),
      ]);

      // 'a' is now some other class: the rest is not an id, so the key is
      // found by shape, with the class name 'aB'.
      expect(_at(short, 'aB$_id', {'messages': <Object>[]}), 'chat_$_id');
      expect(_at(short, 'a$_id', {'messages': <Object>[]}), 'chat_$_id');
      expect(_at(short, 'a', {'messages': <Object>[]}), 'chat_');
    });

    test('takes the longest id a variable-length pattern accepts', () {
      final numbered = LegacyTokens.match([
        LegacyStore(
          prefix: 'note_',
          fields: const ['text'],
          idPattern: RegExp(r'\d+'),
        ),
      ]);

      expect(_at(numbered, 'Qz123', {'text': ''}), 'note_123');
      expect(_at(numbered, 'Qz10', {'text': ''}), 'note_10');
      expect(_at(numbered, 'Q7', {'text': ''}), 'note_7');
    });

    test("keeps idPattern's flags", () {
      final words = LegacyTokens.match([
        LegacyStore(
          prefix: 'word_',
          legacyPrefix: 'WordStore',
          fields: const ['text'],
          idPattern: RegExp(r'\p{Ll}{3}', unicode: true),
        ),
      ]);

      expect(_at(words, 'WordStoreéàü', {'text': ''}), 'word_éàü');
      expect(_at(words, 'Qzéàü', {'text': ''}), 'word_éàü');
    });

    test('never reads keys under current or reserved prefixes', () {
      var reads = 0;
      Object? read() {
        reads++;
        return {'currentUser': 1};
      }

      expect(to('user', read), isNull);
      expect(to('n_1', read), isNull);
      expect(reads, 0);
    });

    test('a type name now given to another class does not move state', () {
      expect(_at(to, 'UserStore', {'messages': <Object>[]}), 'chat_');
      expect(_at(to, 'UserStore', {'unknown': 1}), isNull);
    });

    test('requires the shape to fit exactly one store', () {
      final ambiguous = LegacyTokens.match([
        user,
        const LegacyStore(prefix: 'profile', fields: ['currentUser']),
      ]);

      expect(_at(ambiguous, 'aB', {'currentUser': 1}), isNull);
      expect(_at(to, 'aB', {'currentUser': 1, 'extra': 2}), isNull);
      expect(_at(to, 'aB', {'settings': 2}), isNull);
      expect(_at(to, 'aB', {'tags': <Object>[]}), isNull);
      expect(_at(to, 'aB', {'tags': <Object>[], 'count': 0}), 'tags');
    });

    test('leaves current and reserved prefixes, and non-type keys, alone', () {
      expect(_at(to, 'user', {'currentUser': 1}), isNull);
      expect(_at(to, 'chat_$_id', {'messages': <Object>[]}), isNull);
      expect(_at(to, 'n_1', {'currentUser': 1}), isNull);
      expect(_at(to, 'some.key', {'currentUser': 1}), isNull);
      expect(_at(to, 'Qz-not-an-id', {'messages': <Object>[]}), isNull);
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
