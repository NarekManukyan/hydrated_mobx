import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import '../app/app_observer.dart';
import '../stores/profile_store.dart';
import '../widgets/demo_page.dart';

/// What each schema version wrote, as an old build would have left it.
const _kLegacy = <int, Map<String, dynamic>>{
  1: {'user': 'Ann Lee'},
  2: {'name': 'Ann', 'bio': 'Written by v2'},
  3: {'displayName': 'Ann', 'bio': 'Written by v3'},
};

class MigrationPage extends StatefulWidget {
  const MigrationPage({super.key});

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  ProfileStore? _store;
  int? _seededVersion;

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  /// Leaves [version]'s data on disk, as an older build would have, then
  /// creates the store, which migrates it on hydration.
  Future<void> _seed(int version) async {
    _store?.dispose();
    await HydratedMobX.deleteToken(kProfileToken);
    await HydratedMobX.importData(
      {kProfileToken: Map.of(_kLegacy[version]!)},
      version: version,
    );
    setState(() {
      _seededVersion = version;
      _store = ProfileStore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final storage = HydratedMobX.storage;
    return DemoPage(
      title: 'Schema migration',
      explainer: 'ProfileStore is at version 3. Seed what an older build '
          'wrote: v2 data has its "name" renamed to "displayName"; v1 data '
          'is too old, so migrate returns null and it is dropped.',
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final version in _kLegacy.keys)
              FilledButton.tonal(
                key: Key('seed_v$version'),
                onPressed: () => _seed(version),
                child: Text('Seed v$version data'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_seededVersion case final version?)
          Section(
            title: 'Seeded v$version',
            children: [
              KeyValueTile(storageKey: kProfileToken, value: _kLegacy[version]),
            ],
          ),
        if (store != null)
          Section(
            title: 'After hydration',
            children: [
              Observer(
                builder: (_) => StatRow(
                  tiles: [
                    StatTile(
                      label: 'displayName',
                      value: store.displayName.isEmpty
                          ? '(empty)'
                          : store.displayName,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('bio: ${store.bio.isEmpty ? '(empty)' : store.bio}'),
              const SizedBox(height: 8),
              FutureBuilder<void>(
                // The migrated state is written back by the store's first
                // persistence run; flush waits for it.
                future: store.flush(),
                builder: (context, _) => Column(
                  children: [
                    KeyValueTile(
                      storageKey: kProfileToken,
                      value: storage.read(kProfileToken),
                    ),
                    KeyValueTile(
                      storageKey: HydratedMobX.versionKeyOf(kProfileToken),
                      value: storage.read(
                        HydratedMobX.versionKeyOf(kProfileToken),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        Section(
          title: 'Observer: onMigrate',
          children: [
            Observer(
              builder: (_) {
                final migrations = [
                  for (final entry in appObserver.log)
                    if (entry.kind == LogKind.migration) entry,
                ];
                if (migrations.isEmpty) return const Text('(none yet)');
                return Column(
                  children: [
                    for (final entry in migrations)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.upgrade),
                        title: Text('${entry.token}: ${entry.message}'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
