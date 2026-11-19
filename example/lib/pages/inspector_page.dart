import 'package:flutter/material.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import '../app/app_storages.dart';
import '../widgets/demo_page.dart';
import '../widgets/live_storage_keys.dart';

class InspectorPage extends StatelessWidget {
  const InspectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      title: 'Storage inspector',
      explainer:
          'Every key in every storage, live, via Storage.keys; large '
          'storages list keys only. Deleting goes through '
          'HydratedMobX.deleteToken, which also removes the '
          "key's version and stops a live store from writing it back.",
      children: [
        for (final MapEntry(key: name, value: (:storage, :large))
            in appStorages.all.entries)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LiveStorageKeys(
                title: name,
                storage: storage,
                showValues: !large,
                onDelete: (key) => HydratedMobX.deleteToken(
                  HydratedMobX.tokenOfKey(key),
                  storage: storage(),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => HydratedMobX.clearAll(storage: storage()),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text('Clear $name'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
