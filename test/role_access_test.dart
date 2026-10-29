import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/auth/app_user.dart';
import 'package:library_app/auth/auth_notifier.dart';
import 'package:library_app/auth/permissions.dart';
import 'package:library_app/auth/role.dart';
import 'package:library_app/core/api_exceptions.dart';
import 'package:library_app/models/author.dart';
import 'package:library_app/models/genre.dart';
import 'package:library_app/models/simple_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Проверка прав на стороне сервера: что бы ни показывал интерфейс,
/// решение об операции принимает сервер.
void main() {
  late FakeServer server;

  setUp(() {
    server = FakeServer();
    // Автор без книг: на него не действует запрет удаления из-за связей.
    server.data['authors']!.add({
      'id': 50,
      'fullName': 'Без книг',
      'birthYear': 1900,
      'country': 'Россия',
      'deletedAt': null,
    });
  });

  SimpleQuery loansQuery() =>
      SimpleQuery.initial(sortFields: kLoanSortFields, defaultSort: 'issuedAt');

  group('Читатель', () {
    test('1. не создаёт жанры: 403', () async {
      final repos = await makeRepositories(server, user: 'reader');

      await expectLater(
        repos.genres.create(const Genre(id: 0, name: 'Эссе')),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('2. не удаляет авторов: 403 и запись остаётся', () async {
      final repos = await makeRepositories(server, user: 'reader');

      await expectLater(repos.authors.softDelete(50), throwsA(isA<ForbiddenException>()));

      expect(server.data['authors']!.last['deletedAt'], isNull);
    });

    test('3. видит только свои выдачи', () async {
      final repos = await makeRepositories(server, user: 'reader');

      final page = await repos.loans.find(loansQuery());

      expect(page.items, isNotEmpty);
      expect(page.items.every((loan) => loan.readerId == 1), isTrue);
    });

    test('4. не получает список пользователей: 403', () async {
      final repos = await makeRepositories(server, user: 'reader');

      await expectLater(repos.users.find(), throwsA(isA<ForbiddenException>()));
    });

    test('5. не оформляет выдачи и не принимает книги: 403', () async {
      final repos = await makeRepositories(server, user: 'reader');

      await expectLater(
        repos.loans.issue(readerId: 1, bookId: 1, days: 7),
        throwsA(isA<ForbiddenException>()),
      );
      await expectLater(repos.loans.markReturned(1), throwsA(isA<ForbiddenException>()));
    });

    test('6. продлевает свою выдачу, но не чужую', () async {
      final repos = await makeRepositories(server, user: 'reader');

      final extended = await repos.loans.extend(3);
      expect(extended.dueAt!.year, 2026);

      await expectLater(repos.loans.extend(2), throwsA(isA<ForbiddenException>()));
    });
  });

  group('Библиотекарь', () {
    test('7. создаёт и мягко удаляет записи', () async {
      final repos = await makeRepositories(server, user: 'librarian');

      final created = await repos.authors.create(
        const Author(id: 0, fullName: 'Чехов А. П.', country: 'Россия', birthYear: 1860),
      );
      await repos.authors.softDelete(created.id);

      expect((await repos.authors.findById(created.id))?.isDeleted, isTrue);
    });

    test('8. не удаляет физически и не восстанавливает: 403', () async {
      final repos = await makeRepositories(server, user: 'librarian');

      await expectLater(repos.authors.hardDelete(50), throwsA(isA<ForbiddenException>()));
      await expectLater(repos.authors.restore(50), throwsA(isA<ForbiddenException>()));
      expect(server.data['authors'], hasLength(3));
    });

    test('9. видит все выдачи', () async {
      final repos = await makeRepositories(server, user: 'librarian');

      final page = await repos.loans.find(loansQuery());

      expect(page.total, 3);
    });

    test('10. не управляет пользователями: 403', () async {
      final repos = await makeRepositories(server, user: 'librarian');

      await expectLater(repos.users.find(), throwsA(isA<ForbiddenException>()));
      await expectLater(repos.users.changeRole(3, Role.admin), throwsA(isA<ForbiddenException>()));
    });
  });

  group('Администратор', () {
    test('11. удаляет физически и восстанавливает', () async {
      final repos = await makeRepositories(server, user: 'admin');

      await repos.authors.softDelete(50);
      expect((await repos.authors.findById(50))?.isDeleted, isTrue);
      await repos.authors.restore(50);
      expect((await repos.authors.findById(50))?.isDeleted, isFalse);

      await repos.authors.hardDelete(50);
      expect(await repos.authors.findById(50), isNull);
    });

    test('12. видит пользователей и меняет роль', () async {
      final repos = await makeRepositories(server, user: 'admin');

      final page = await repos.users.find();
      expect(page.total, 3);

      final changed = await repos.users.changeRole(3, Role.librarian);
      expect(changed.role, Role.librarian);
      expect(server.users.firstWhere((u) => u.id == 3).role, 'librarian');
    });
  });

  group('Подмена роли в localStorage (пункт 17 задания)', () {
    test('интерфейс верит подменённой роли, а сервер отвечает 403', () async {
      // Читатель вошёл, токены лежат в localStorage.
      final repos = await makeRepositories(server, user: 'reader');
      final prefs = await SharedPreferences.getInstance();
      expect(repos.auth.can(Permission.manageCatalog), isFalse);

      // Злоумышленник правит профиль в localStorage: role -> admin.
      final tampered = AppUser.fromJson({
        'id': 3,
        'username': 'reader',
        'fullName': 'Смирнов П. А.',
        'role': 'admin',
        'readerId': 1,
      });
      await prefs.setString(kUserKey, _json(tampered));

      // Страница перезагружена: клиент читает профиль из localStorage.
      final reloaded = await makeAuth(server, prefs);
      await reloaded.restore();
      expect(reloaded.role, Role.admin, reason: 'интерфейс обманут: кнопки появятся');
      expect(reloaded.can(Permission.manageCatalog), isTrue);
      expect(reloaded.can(Permission.manageUsers), isTrue);

      // Но токен остался читательским, поэтому операция отклоняется сервером.
      final attack = await makeRepositories(server, user: null, prefs: prefs);
      await attack.auth.restore();
      await expectLater(
        attack.genres.create(const Genre(id: 0, name: 'Взлом')),
        throwsA(isA<ForbiddenException>()),
      );
      await expectLater(attack.users.find(), throwsA(isA<ForbiddenException>()));
      expect(server.data['genres'], hasLength(2), reason: 'данные не изменились');
    });

    test('после обновления токена роль в интерфейсе исправляется данными сервера', () async {
      await makeRepositories(server, user: 'reader');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kUserKey,
        _json(const AppUser(id: 3, username: 'reader', fullName: 'Смирнов П. А.', role: Role.admin, readerId: 1)),
      );
      final reloaded = await makeAuth(server, prefs);
      await reloaded.restore();
      expect(reloaded.role, Role.admin);

      await reloaded.refreshTokens();

      expect(reloaded.role, Role.reader);
    });
  });
}

String _json(AppUser user) => jsonEncode(user.toJson());
