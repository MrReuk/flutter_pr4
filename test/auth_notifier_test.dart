import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/auth/auth_notifier.dart';
import 'package:library_app/auth/permissions.dart';
import 'package:library_app/auth/role.dart';
import 'package:library_app/auth/session_policy.dart';
import 'package:library_app/core/api_exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  late FakeServer server;
  late SharedPreferences prefs;
  late DateTime clock;
  late AuthNotifier auth;

  const policy = SessionPolicy(
    inactivity: Duration(seconds: 180),
    warning: Duration(seconds: 30),
    maxDuration: Duration(hours: 8),
  );

  Future<AuthNotifier> newAuth() => makeAuth(server, prefs, policy: policy, now: () => clock);

  setUp(() async {
    server = FakeServer();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    clock = DateTime(2026, 10, 29, 9);
    auth = await newAuth();
  });

  tearDown(() => auth.dispose());

  group('Вход', () {
    test('успешный вход запоминает пользователя и токены', () async {
      await auth.login('reader', 'reader123');

      expect(auth.isAuthenticated, isTrue);
      expect(auth.user?.fullName, 'Смирнов П. А.');
      expect(auth.role, Role.reader);
      expect(auth.accessToken, isNotNull);
      expect(prefs.getString(kAccessKey), auth.accessToken);
      expect(prefs.getString(kRefreshKey), isNotNull);
      expect(prefs.getString(kUserKey), contains('"role":"reader"'));
    });

    test('неверный пароль: понятная ошибка, ничего не сохраняется', () async {
      await expectLater(
        auth.login('reader', 'неверный'),
        throwsA(
          isA<UnauthorizedException>().having((e) => e.message, 'сообщение', 'Неверный логин или пароль'),
        ),
      );

      expect(auth.isAuthenticated, isFalse);
      expect(prefs.getKeys(), isEmpty);
      expect(server.refreshCount, 0, reason: 'ошибка входа не должна вызывать обновление токена');
    });

    test('права зависят от роли вошедшего', () async {
      await auth.login('librarian', 'librarian123');

      expect(auth.can(Permission.manageCatalog), isTrue);
      expect(auth.can(Permission.manageUsers), isFalse);
      expect(auth.has(Role.librarian), isTrue);
      expect(auth.has(Role.admin), isFalse);
    });
  });

  group('Выход', () {
    test('очищает токены, профиль и время активности', () async {
      await auth.login('admin', 'admin123');
      expect(prefs.getKeys(), isNotEmpty);

      await auth.logout();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.accessToken, isNull);
      expect(prefs.getString(kAccessKey), isNull);
      expect(prefs.getString(kRefreshKey), isNull);
      expect(prefs.getString(kUserKey), isNull);
      expect(prefs.getInt(kActivityKey), isNull);
      expect(auth.lastEnd, SessionEnd.manual);
    });

    test('сообщает серверу, какой токен обновления аннулировать', () async {
      await auth.login('admin', 'admin123');
      final refresh = prefs.getString(kRefreshKey);

      await auth.logout();

      final call = server.calls('POST', '/auth/logout').single;
      expect((call.data as Map)['refreshToken'], refresh);
    });

    test('повторный выход ничего не ломает и не обращается к серверу', () async {
      await auth.logout();

      expect(server.calls('POST', '/auth/logout'), isEmpty);
      expect(auth.lastEnd, isNull);
    });
  });

  group('Сессия после перезагрузки страницы', () {
    test('токены и профиль переживают перезагрузку', () async {
      await auth.login('reader', 'reader123');
      final token = auth.accessToken;

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.isAuthenticated, isTrue);
      expect(reloaded.user?.username, 'reader');
      expect(reloaded.accessToken, token);
      expect(server.calls('GET', '/auth/me'), isEmpty, reason: 'профиль взят из localStorage');
    });

    test('если профиля в хранилище нет, он запрашивается у сервера', () async {
      await auth.login('librarian', 'librarian123');
      await prefs.remove(kUserKey);

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.role, Role.librarian);
      expect(server.calls('GET', '/auth/me'), hasLength(1));
    });

    test('повреждённый профиль не принимается', () async {
      await auth.login('librarian', 'librarian123');
      await prefs.setString(kUserKey, '{не json');

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.role, Role.librarian);
      expect(server.calls('GET', '/auth/me'), hasLength(1));
    });

    test('без сохранённых токенов восстанавливать нечего', () async {
      await auth.restore();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.isUnverified, isFalse);
    });

    test('через три минуты без действий сессия после перезагрузки не восстанавливается', () async {
      await auth.login('reader', 'reader123');
      clock = clock.add(const Duration(seconds: 181));

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.isAuthenticated, isFalse);
      expect(reloaded.lastEnd, SessionEnd.inactivity);
      expect(prefs.getString(kAccessKey), isNull);
    });

    test('действие пользователя продлевает срок бездействия', () async {
      await auth.login('reader', 'reader123');
      clock = clock.add(const Duration(seconds: 150));
      auth.touch();
      clock = clock.add(const Duration(seconds: 150));

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.isAuthenticated, isTrue);
    });

    test('предельная длительность сессии действует и при активном пользователе', () async {
      await auth.login('reader', 'reader123');
      clock = clock.add(const Duration(hours: 8, seconds: 1));
      await prefs.setInt(kActivityKey, clock.millisecondsSinceEpoch);

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.isAuthenticated, isFalse);
      expect(reloaded.lastEnd, SessionEnd.maxDuration);
    });

    test('недоступный сервер не сбрасывает сессию, токены остаются', () async {
      await auth.login('reader', 'reader123');
      await prefs.remove(kUserKey);
      server.down = true;

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.isUnverified, isTrue);
      expect(reloaded.isAuthenticated, isFalse);
      expect(prefs.getString(kAccessKey), isNotNull);
      expect(prefs.getString(kRefreshKey), isNotNull);

      server.down = false;
      await reloaded.restore();
      expect(reloaded.isAuthenticated, isTrue);
      expect(reloaded.isUnverified, isFalse);
    });

    test('истёкший токен доступа при старте обновляется токеном обновления', () async {
      await auth.login('reader', 'reader123');
      await prefs.remove(kUserKey);
      server.expireAccess();

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.isAuthenticated, isTrue);
      expect(server.refreshCount, 1);
    });

    test('отклонённый токен обновления при старте даёт чистый выход', () async {
      await auth.login('reader', 'reader123');
      await prefs.remove(kUserKey);
      server.expireAccess();
      server.expireRefresh();

      final reloaded = await newAuth();
      addTearDown(reloaded.dispose);
      await reloaded.restore();

      expect(reloaded.isAuthenticated, isFalse);
      expect(reloaded.lastEnd, SessionEnd.tokenRejected);
      expect(prefs.getString(kAccessKey), isNull);
    });
  });

  group('Обновление токена', () {
    test('параллельные вызовы делят один запрос', () async {
      await auth.login('admin', 'admin123');
      server.refreshDelay = const Duration(milliseconds: 20);

      await Future.wait([auth.refreshTokens(), auth.refreshTokens(), auth.refreshTokens()]);

      expect(server.refreshCount, 1);
    });

    test('новая пара токенов сохраняется, а роль берётся у сервера', () async {
      await auth.login('reader', 'reader123');
      final before = auth.accessToken;
      server.users.firstWhere((u) => u.username == 'reader').role = 'librarian';

      await auth.refreshTokens();

      expect(auth.accessToken, isNot(before));
      expect(prefs.getString(kAccessKey), auth.accessToken);
      expect(auth.role, Role.librarian);
    });

    test('без токена обновления вход нужен заново', () async {
      await expectLater(auth.refreshTokens(), throwsA(isA<UnauthorizedException>()));
      expect(server.refreshCount, 0);
    });
  });

  group('Регистрация', () {
    test('создаёт пользователя с ролью читателя и сразу входит', () async {
      await auth.register(
        username: 'newbie',
        password: 'abcdef1!',
        fullName: 'Новиков Н. Н.',
        email: '',
      );

      expect(auth.isAuthenticated, isTrue);
      expect(auth.role, Role.reader);
      expect(auth.user?.username, 'newbie');
    });

    test('занятый логин возвращается как ошибка поля', () async {
      await expectLater(
        auth.register(username: 'admin', password: 'abcdef1!', fullName: 'Дубль', email: ''),
        throwsA(
          isA<ValidationException>().having((e) => e.errors['username'], 'ошибка логина', 'Такой логин уже занят'),
        ),
      );
      expect(auth.isAuthenticated, isFalse);
    });
  });
}
