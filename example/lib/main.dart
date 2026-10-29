import 'package:flutter/material.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app_observer.dart';
import 'app/app_storages.dart';
import 'pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // An app upgrading from 1.x keeps the directory it used before (the 1.x
  // docs used Documents); a new one opens an empty box.
  final directory = await getApplicationSupportDirectory();
  appStorages = await AppStorages.build(directory.path);
  // The default storage for stores built without `storage:`.
  HydratedMobX.storage = appStorages.main;
  // One place for every store's errors and migrations.
  HydratedMobX.observer = appObserver;

  // Write state that a persistDelay is still holding back before the OS may
  // kill the backgrounded app.
  AppLifecycleListener(onPause: HydratedMobX.flushAll);

  runApp(const HydratedMobXExampleApp());
}

class HydratedMobXExampleApp extends StatelessWidget {
  const HydratedMobXExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: brightness,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'hydrated_mobx',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomePage(),
    );
  }
}
