import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/app.dart';
import 'package:library_app/app_repositories.dart';
import 'package:library_app/auth/auth_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_harness.dart';
import 'test_helpers.dart';

Future<void> _login(WidgetTester tester, String username, String password) async {
  await tester.enterText(find.byKey(const ValueKey('login-username')), username);
  await tester.enterText(find.byKey(const ValueKey('login-password')), password);
  await tester.tap(find.byKey(const ValueKey('login-submit')));
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  FakeServer server, {
  String? user,
  String location = '/',
}) async {
  useLargeScreen(tester);
  final repos = await signedIn(tester, server, user: user);
  await tester.pumpWidget(LibraryApp(repositories: repos, initialLocation: location));
  await tester.pumpAndSettle();
}

void main() {
  late FakeServer server;

  setUp(() => server = FakeServer());

  group('Вход и выход', () {
    testWidgets('без входа защищённый адрес открывает форму входа', (tester) async {
      await _open(tester, server, location: '/books');

      expect(find.text('Вход в систему'), findsOneWidget);
      expect(find.text('Идиот'), findsNothing);
      expect(server.protectedCalls.where((r) => r.uri.path == '/api/books'), isEmpty);
    });

    testWidgets('пустая форма входа показывает ошибки обязательных полей', (tester) async {
      await _open(tester, server, location: '/login');

      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Введите логин'), findsOneWidget);
      expect(find.text('Введите пароль'), findsOneWidget);
      expect(server.loginCount, 0);
    });

    testWidgets('неверный пароль: понятное сообщение, форма остаётся', (tester) async {
      await _open(tester, server, location: '/login');

      await _login(tester, 'reader', 'неверный');

      expect(find.text('Неверный логин или пароль'), findsOneWidget);
      expect(find.text('Вход в систему'), findsOneWidget);
      expect(server.refreshCount, 0);
    });

    testWidgets('после входа пользователь возвращается на адрес из параметра from', (tester) async {
      await _open(tester, server, location: '/books?search=идиот');
      expect(find.text('Вход в систему'), findsOneWidget);

      await _login(tester, 'reader', 'reader123');

      expect(find.text('Вход в систему'), findsNothing);
      expect(find.text('Идиот'), findsWidgets);
      expect(find.textContaining('Здравствуйте'), findsNothing);
      expect(find.text('Преступление и наказание'), findsNothing, reason: 'параметры поиска сохранились');
    });

    testWidgets('после входа без адреса возврата открывается главная с именем в шапке', (tester) async {
      await _open(tester, server, location: '/login');

      await _login(tester, 'reader', 'reader123');

      expect(find.text('Здравствуйте, Смирнов П. А.!'), findsOneWidget);
      expect(find.text('Смирнов П. А.'), findsOneWidget, reason: 'имя в шапке');
      expect(find.text('Роль: Читатель'), findsOneWidget);
    });

    testWidgets('выход очищает токены и возвращает на экран входа', (tester) async {
      await _open(tester, server, user: 'admin');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kAccessKey), isNotNull);

      await tester.tap(find.byKey(const ValueKey('user-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выйти'));
      await tester.pumpAndSettle();

      expect(find.text('Вход в систему'), findsOneWidget);
      expect(find.text('Вы вышли из системы.'), findsOneWidget);
      expect(prefs.getString(kAccessKey), isNull);
      expect(prefs.getString(kRefreshKey), isNull);
      expect(server.calls('POST', '/auth/logout'), hasLength(1));
    });

    testWidgets('уже вошедший пользователь, открыв /login, попадает на главную', (tester) async {
      await _open(tester, server, user: 'librarian', location: '/login');

      expect(find.text('Вход в систему'), findsNothing);
      expect(find.textContaining('Здравствуйте'), findsOneWidget);
    });
  });

  group('Регистрация', () {
    Future<void> typeRegistration(WidgetTester tester, {required String password}) async {
      await tester.enterText(find.byKey(const ValueKey('register-fullName')), 'Новиков Н. Н.');
      await tester.enterText(find.byKey(const ValueKey('register-username')), 'novikov');
      await tester.enterText(find.byKey(const ValueKey('register-password')), password);
      await tester.enterText(find.byKey(const ValueKey('register-repeat')), password);
      await tester.pump();
    }

    testWidgets('правила пароля отмечаются по мере ввода', (tester) async {
      await _open(tester, server, location: '/register');
      expect(find.byIcon(Icons.check_circle), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('register-password')), 'abcdefgh');
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'выполнена только длина');

      await tester.enterText(find.byKey(const ValueKey('register-password')), 'abcdefg1');
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

      await tester.enterText(find.byKey(const ValueKey('register-password')), 'abcdef1!');
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    });

    testWidgets('слабый пароль не отправляется на сервер', (tester) async {
      await _open(tester, server, location: '/register');

      await typeRegistration(tester, password: 'abcdefg1');
      await tester.tap(find.byKey(const ValueKey('register-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('специальный символ'), findsWidgets);
      expect(server.calls('POST', '/auth/register'), isEmpty);
    });

    testWidgets('несовпадающие пароли отклоняются', (tester) async {
      await _open(tester, server, location: '/register');

      await typeRegistration(tester, password: 'abcdef1!');
      await tester.enterText(find.byKey(const ValueKey('register-repeat')), 'abcdef1?');
      await tester.tap(find.byKey(const ValueKey('register-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Пароли не совпадают'), findsOneWidget);
      expect(server.calls('POST', '/auth/register'), isEmpty);
    });

    testWidgets('корректная регистрация сразу входит под новой учётной записью', (tester) async {
      await _open(tester, server, location: '/register');

      await typeRegistration(tester, password: 'abcdef1!');
      await tester.tap(find.byKey(const ValueKey('register-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Здравствуйте, Новиков Н. Н.!'), findsOneWidget);
      expect(find.text('Роль: Читатель'), findsOneWidget);
    });
  });

  group('Интерфейс зависит от роли', () {
    testWidgets('читатель: свой набор разделов и нет разделов персонала', (tester) async {
      await _open(tester, server, user: 'reader');

      expect(find.text('Мои выдачи'), findsWidgets);
      for (final hidden in ['Читатели', 'Выдачи', 'Рабочее место', 'Пользователи', 'Статистика']) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
    });

    testWidgets('библиотекарь: рабочее место и выдачи, но не администрирование', (tester) async {
      await _open(tester, server, user: 'librarian');

      expect(find.text('Рабочее место'), findsWidgets);
      expect(find.text('Читатели'), findsWidgets);
      expect(find.text('Мои выдачи'), findsNothing);
      expect(find.text('Пользователи'), findsNothing);
      expect(find.text('Статистика'), findsNothing);
    });

    testWidgets('администратор: пользователи и статистика', (tester) async {
      await _open(tester, server, user: 'admin');

      expect(find.text('Пользователи'), findsWidgets);
      expect(find.text('Статистика'), findsWidgets);
      expect(find.text('Рабочее место'), findsNothing);
      expect(find.text('Мои выдачи'), findsNothing);
    });

    testWidgets('читатель не видит кнопок изменения в списке жанров', (tester) async {
      await _open(tester, server, user: 'reader', location: '/genres');

      expect(find.text('Роман'), findsWidgets);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.delete_forever), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('библиотекарь видит изменение и мягкое удаление, но не удаление навсегда', (tester) async {
      await _open(tester, server, user: 'librarian', location: '/genres');

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
      expect(find.byIcon(Icons.delete_forever), findsNothing);
    });

    testWidgets('администратору доступно и удаление навсегда', (tester) async {
      await _open(tester, server, user: 'admin', location: '/genres');

      expect(find.byIcon(Icons.delete_forever), findsWidgets);
    });

    testWidgets('читатель видит сводку по своим выдачам', (tester) async {
      await _open(tester, server, user: 'reader');

      expect(find.text('На руках: 2'), findsOneWidget);
      expect(find.text('Просрочено: 1'), findsOneWidget);
    });
  });

  group('Защита маршрутов', () {
    testWidgets('читатель на адресе администратора видит экран отказа без запроса данных', (tester) async {
      await _open(tester, server, user: 'reader', location: '/admin/users');

      expect(find.text('Доступ запрещён'), findsOneWidget);
      expect(find.textContaining('нет доступа к этому разделу'), findsOneWidget);
      expect(find.textContaining('/admin/users'), findsOneWidget);
      expect(server.calls('GET', '/users'), isEmpty);
    });

    testWidgets('читателю закрыта форма создания книги', (tester) async {
      await _open(tester, server, user: 'reader', location: '/books/new');

      expect(find.text('Доступ запрещён'), findsOneWidget);
      expect(find.text('Новая книга'), findsNothing);
    });

    testWidgets('читателю закрыт список читателей', (tester) async {
      await _open(tester, server, user: 'reader', location: '/readers');

      expect(find.text('Доступ запрещён'), findsOneWidget);
      expect(server.calls('GET', '/readers'), isEmpty);
    });

    testWidgets('библиотекарь не открывает статистику', (tester) async {
      await _open(tester, server, user: 'librarian', location: '/admin/stats');
      expect(find.text('Доступ запрещён'), findsOneWidget);
    });

    testWidgets('администратору закрыто рабочее место библиотекаря', (tester) async {
      await _open(tester, server, user: 'admin', location: '/desk');
      expect(find.text('Доступ запрещён'), findsOneWidget);
    });

    testWidgets('администратор открывает раздел пользователей', (tester) async {
      await _open(tester, server, user: 'admin', location: '/admin/users');

      expect(find.text('Пользователи и роли'), findsOneWidget);
      expect(find.byKey(const ValueKey('user-3')), findsOneWidget);
    });

    testWidgets('кнопка на экране отказа возвращает на главную', (tester) async {
      await _open(tester, server, user: 'reader', location: '/desk');
      expect(find.text('Доступ запрещён'), findsOneWidget);

      await tester.tap(find.text('На главную'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Здравствуйте'), findsOneWidget);
    });
  });

  group('Разделы ролей', () {
    testWidgets('читатель продлевает свою выдачу', (tester) async {
      await _open(tester, server, user: 'reader', location: '/my/loans');

      expect(find.byKey(const ValueKey('my-loan-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('my-loan-2')), findsNothing, reason: 'чужая выдача');
      expect(
        find.descendant(of: find.byKey(const ValueKey('my-loan-1')), matching: find.text('Продлить')),
        findsNothing,
        reason: 'просроченную продлить нельзя',
      );

      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('my-loan-3')), matching: find.text('Продлить')),
      );
      await tester.pumpAndSettle();

      expect(server.calls('POST', '/loans/3/extend'), hasLength(1));
    });

    testWidgets('библиотекарь принимает книгу на рабочем месте', (tester) async {
      await _open(tester, server, user: 'librarian', location: '/desk');

      expect(find.byKey(const ValueKey('desk-loan-3')), findsOneWidget);

      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('desk-loan-3')), matching: find.text('Принять')),
      );
      await tester.pumpAndSettle();

      expect(server.calls('POST', '/loans/3/return'), hasLength(1));
    });

    testWidgets('администратор меняет роль пользователя после подтверждения', (tester) async {
      await _open(tester, server, user: 'admin', location: '/admin/users');

      await tester.tap(find.byKey(const ValueKey('role-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Библиотекарь').last);
      await tester.pumpAndSettle();
      expect(find.text('Изменить роль?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Изменить'));
      await tester.pumpAndSettle();

      expect(server.calls('PATCH', '/users/3'), hasLength(1));
      expect(server.users.firstWhere((u) => u.id == 3).role, 'librarian');
    });

    testWidgets('статистика администратора считается по данным сервера', (tester) async {
      await _open(tester, server, user: 'admin', location: '/admin/stats');

      Finder number(String label, String value) => find.descendant(
            of: find.byKey(ValueKey('stat-$label')),
            matching: find.text(value),
          );
      expect(number('Книги', '4'), findsOneWidget);
      expect(number('Выдано сейчас', '2'), findsOneWidget);
      expect(number('Просрочено', '1'), findsOneWidget);
      expect(number('Пользователи', '3'), findsOneWidget);
    });
  });

  group('Жизненный цикл сессии', () {
    testWidgets('нерабочий токен обновления: чистый выход, один запрос обновления, повторный вход возвращает на страницу',
        (tester) async {
      await _open(tester, server, user: 'reader', location: '/books');
      expect(find.text('Идиот'), findsWidgets);

      server.expireAccess();
      server.refreshRejected = true;
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Авторы')));
      await tester.pumpAndSettle();

      expect(find.text('Вход в систему'), findsOneWidget);
      expect(find.textContaining('сервер не принял токен'), findsOneWidget);
      expect(server.refreshCount, 1, reason: 'цикла запросов нет');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kAccessKey), isNull);

      await _login(tester, 'reader', 'reader123');
      expect(find.text('Достоевский Ф. М.'), findsWidgets, reason: 'возврат на /authors');
    });

    testWidgets('истёкший токен обновляется незаметно для пользователя', (tester) async {
      await _open(tester, server, user: 'reader', location: '/books');

      server.expireAccess();
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Авторы')));
      await tester.pumpAndSettle();

      expect(find.text('Достоевский Ф. М.'), findsWidgets);
      expect(find.text('Вход в систему'), findsNothing);
      expect(server.refreshCount, 1);
    });

    testWidgets('предупреждение за 30 секунд, продление кнопкой и выход после трёх минут', (tester) async {
      useLargeScreen(tester);
      var clock = DateTime(2026, 10, 29, 9);
      final repos = await signedIn(tester, server, user: 'reader', now: () => clock);
      await tester.pumpWidget(LibraryApp(repositories: repos, clock: () => clock));
      await tester.pumpAndSettle();
      const warning = ValueKey('session-warning');
      expect(find.byKey(warning), findsNothing);

      // 2 минуты 30 секунд без действий: показано предупреждение.
      clock = clock.add(const Duration(seconds: 150));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(warning), findsOneWidget);
      expect(find.textContaining('Через 30 с'), findsOneWidget);

      // «Остаться в системе» сбрасывает отсчёт.
      await tester.tap(find.byKey(const ValueKey('session-stay')));
      await tester.pump();
      expect(find.byKey(warning), findsNothing);

      // Снова бездействие: предупреждение, затем выход.
      clock = clock.add(const Duration(seconds: 150));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(warning), findsOneWidget);

      clock = clock.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byKey(warning), findsNothing);
      expect(find.text('Вход в систему'), findsOneWidget);
      expect(find.textContaining('долго не было действий'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kAccessKey), isNull);
    });

    testWidgets('кнопка «Выйти» в предупреждении завершает сессию сразу', (tester) async {
      useLargeScreen(tester);
      var clock = DateTime(2026, 10, 29, 9);
      final repos = await signedIn(tester, server, user: 'admin', now: () => clock);
      await tester.pumpWidget(LibraryApp(repositories: repos, clock: () => clock));
      await tester.pumpAndSettle();

      clock = clock.add(const Duration(seconds: 160));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('session-leave')));
      await tester.pumpAndSettle();

      expect(find.text('Вход в систему'), findsOneWidget);
    });

    testWidgets('предельная длительность сессии прерывает работу активного пользователя', (tester) async {
      useLargeScreen(tester);
      var clock = DateTime(2026, 10, 29, 9);
      final repos = await signedIn(tester, server, user: 'admin', now: () => clock);
      await tester.pumpWidget(LibraryApp(repositories: repos, clock: () => clock));
      await tester.pumpAndSettle();

      // Пользователь всё время что-то делает, но восемь часов прошли.
      clock = clock.add(const Duration(hours: 8, seconds: 1));
      await tester.tap(find.byKey(const ValueKey('user-menu')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Вход в систему'), findsOneWidget);
      expect(find.textContaining('длительность сессии'), findsOneWidget);
    });
  });

  group('Подмена роли в localStorage', () {
    testWidgets('кнопки появляются, но сервер отвечает 403 и интерфейс объясняет причину', (tester) async {
      useLargeScreen(tester);
      await signedIn(tester, server, user: 'reader');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kUserKey,
        jsonEncode({
          'id': 3,
          'username': 'reader',
          'fullName': 'Смирнов П. А.',
          'email': '',
          'role': 'admin',
          'readerId': 1,
        }),
      );
      late AppRepositories tampered;
      await tester.runAsync(() async {
        tampered = await makeRepositories(server, user: null, prefs: prefs);
        await tampered.auth.restore();
      });

      await tester.pumpWidget(LibraryApp(repositories: tampered, initialLocation: '/genres'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsOneWidget, reason: 'интерфейс считает читателя администратором');
      expect(find.byIcon(Icons.delete_forever), findsWidgets);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Название *'), 'Взлом');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Недостаточно прав для этого действия'), findsOneWidget);
      expect(server.data['genres'], hasLength(2));
      expect(server.calls('POST', '/genres').single.headers['Authorization'], startsWith('Bearer access-'));
    });
  });
}
