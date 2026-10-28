import 'package:flutter/material.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import '../app/app_storages.dart';
import '../widgets/demo_page.dart';
import '../widgets/live_box_keys.dart';

class InspectorPage extends StatelessWidget {
  const InspectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      title: 'Storage inspector',
      explainer: 'Every key in every box, live, via Storage.keys. Deleting '
          'goes through HydratedMobX.deleteToken, which also removes the '
          "key's version and stops a live store from writing it back.",
      children: [
        for (final MapEntry(key: name, value: storage)
            in appStorages.all.entries)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LiveBoxKeys(
                title: name,
                storage: storage,
                // Reading a value refreshes its key's use time, which would
                // keep every key in the capped recent box from eviction.
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
