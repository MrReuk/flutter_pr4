import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_repositories.dart';
import 'core/debug_flags.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final prefs = await SharedPreferences.getInstance();
  final repositories = AppRepositories.connect(
    prefs: prefs,
    debugFlags: readDebugFlags(Uri.base),
  );
  // До первого кадра выясняем, есть ли сохранённая сессия: так страница
  // после перезагрузки сразу открывается нужным экраном, без мигания входа.
  await repositories.auth.restore();
  runApp(LibraryApp(repositories: repositories));
}
