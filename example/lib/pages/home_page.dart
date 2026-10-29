import 'package:flutter/material.dart';

import 'counter_page.dart';
import 'encryption_page.dart';
import 'eviction_page.dart';
import 'inspector_page.dart';
import 'keyed_page.dart';
import 'migration_page.dart';
import 'namespaces_page.dart';
import 'observer_page.dart';
import 'stats_page.dart';
import 'trust_json_page.dart';

class _Demo {
  const _Demo(this.id, this.icon, this.title, this.subtitle, this.page);

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
}

const _kDemos = [
  _Demo(
    'counter',
    Icons.exposure_plus_1,
    'Counter',
    'Persist a store, coalesce writes with persistDelay',
    CounterPage(),
  ),
  _Demo(
    'keyed',
    Icons.view_agenda_outlined,
    'Keyed instances',
    'One store type, many keys via storeId',
    KeyedPage(),
  ),
  _Demo(
    'stats',
    Icons.insights_outlined,
    'Write stats',
    'Writes saved by persistDelay and change detection',
    StatsPage(),
  ),
  _Demo(
    'namespaces',
    Icons.folder_copy_outlined,
    'Namespaces',
    'Session and account boxes, clearAll(where:)',
    NamespacesPage(),
  ),
  _Demo(
    'migration',
    Icons.upgrade,
    'Schema migration',
    'version, migrate, dropping old data with null',
    MigrationPage(),
  ),
  _Demo(
    'eviction',
    Icons.auto_delete_outlined,
    'Eviction',
    'maxEntries and an evictable filter',
    EvictionPage(),
  ),
  _Demo(
    'observer',
    Icons.report_outlined,
    'Observer & errors',
    'One HydratedObserver for every store',
    ObserverPage(),
  ),
  _Demo(
    'inspector',
    Icons.manage_search,
    'Storage inspector',
    'Every key in every box, live',
    InspectorPage(),
  ),
  _Demo(
    'encryption',
    Icons.lock_outline,
    'Encryption',
    'An AES-256 encrypted box',
    EncryptionPage(),
  ),
  _Demo(
    'trust',
    Icons.speed,
    'trustToJson',
    'Skip the traversal for plain-JSON state',
    TrustJsonPage(),
  ),
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('hydrated_mobx 2.0')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _kDemos.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final demo = _kDemos[index];
          return ListTile(
            key: Key('demo_${demo.id}'),
            leading: CircleAvatar(child: Icon(demo.icon)),
            title: Text(demo.title),
            subtitle: Text(demo.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => demo.page)),
          );
        },
      ),
    );
  }
}
