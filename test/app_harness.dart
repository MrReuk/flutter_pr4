import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/app_repositories.dart';
import 'package:library_app/auth/session_policy.dart';

import 'test_helpers.dart';

void useLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Клиент, уже вошедший под [user] (null: без входа). Вход выполняется
/// в настоящем асинхронном режиме, поэтому часы теста не двигаются.
Future<AppRepositories> signedIn(
  WidgetTester tester,
  FakeServer server, {
  String? user = 'admin',
  DateTime Function()? now,
  SessionPolicy policy = const SessionPolicy(),
}) async {
  late AppRepositories repositories;
  await tester.runAsync(() async {
    repositories = await makeRepositories(server, user: user, now: now, policy: policy);
  });
  return repositories;
}
