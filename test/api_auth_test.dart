import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/app_repositories.dart';
import 'package:library_app/auth/auth_notifier.dart';
import 'package:library_app/core/api_exceptions.dart';
import 'package:library_app/models/author_query.dart';
import 'package:library_app/models/book_query.dart';
import 'package:library_app/models/genre.dart';
import 'package:library_app/models/simple_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  late FakeServer server;

  setUp(() => server = FakeServer());

  group('Заголовок Authorization', () {
    test('добавляется ко всем защищённым запросам, в том числе к чтению', () async {
      final repos = await makeRepositories(server, user: 'reader');

      await repos.books.find(const BookQuery());
      await repos.loans.find(
        SimpleQuery.initial(sortFields: kLoanSortFields, defaultSort: 'issuedAt'),
      );

      final token = repos.auth.accessToken;
      expect(server.protectedCalls, hasLength(2));
      for (final call in server.protectedCalls) {
        expect(call.headers['Authorization'], 'Bearer $token');
      }
    });

    test('не добавляется к запросам /auth/*', () async {
      final repos = await makeRepositories(server, user: null);

      await repos.auth.login('reader', 'reader123');
      await repos.auth.refreshTokens();

      for (final call in server.requests.where((r) => r.uri.path.contains('/auth/'))) {
        expect(call.headers.containsKey('Authorization'), isFalse, reason: call.uri.path);
      }
    });

    test('без входа запрос уходит без заголовка и получает 401', () async {
      final repos = await makeRepositories(server, user: null);

      await expectLater(
        repos.books.find(const BookQuery()),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(server.calls('GET', '/books').single.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('Прозрачное обновление токена при 401', () {
    test('просроченный токен обновляется, запрос повторяется один раз', () async {
      final repos = await makeRepositories(server, user: 'reader');
      final oldToken = repos.auth.accessToken;

      server.expireAccess();
      final page = await repos.books.find(const BookQuery());

      expect(page.items, isNotEmpty);
      expect(server.refreshCount, 1);
      expect(server.calls('GET', '/books'), hasLength(2), reason: 'первый запрос получил 401, второй 200');
      expect(repos.auth.accessToken, isNot(oldToken));
      expect(server.calls('GET', '/books').last.headers['Authorization'], 'Bearer ${repos.auth.accessToken}');
      expect(repos.auth.isAuthenticated, isTrue);
    });

    test('запись тоже повторяется после обновления токена', () async {
      final repos = await makeRepositories(server, user: 'librarian');

      server.expireAccess();
      final created = await repos.genres.create(const Genre(id: 0, name: 'Детектив'));

      expect(created.id, greaterThan(0));
      expect(server.calls('POST', '/genres'), hasLength(2));
      expect(server.refreshCount, 1);
    });

    test('несколько параллельных запросов вызывают одно обновление', () async {
      final repos = await makeRepositories(server, user: 'reader');
      server.refreshDelay = const Duration(milliseconds: 20);

      server.expireAccess();
      final results = await Future.wait<Object>([
        repos.books.find(const BookQuery()),
        repos.authors.find(const AuthorQuery()),
        repos.loans.find(
          SimpleQuery.initial(sortFields: kLoanSortFields, defaultSort: 'issuedAt'),
        ),
      ]);

      expect(results, hasLength(3));
      expect(server.refreshCount, 1);
    });

    test('рефреш-токен не принят: чистый выход и ровно одна попытка обновления', () async {
      final repos = await makeRepositories(server, user: 'reader');
      final prefs = await SharedPreferences.getInstance();

      server.expireAccess();
      server.refreshRejected = true;

      await expectLater(
        repos.books.find(const BookQuery()),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(repos.auth.isAuthenticated, isFalse);
      expect(repos.auth.lastEnd, SessionEnd.tokenRejected);
      expect(prefs.getString(kAccessKey), isNull);
      expect(prefs.getString(kRefreshKey), isNull);
      expect(server.refreshCount, 1);
      expect(server.calls('GET', '/books'), hasLength(1), reason: 'запрос не повторяется бесконечно');

      // Следующий запрос уже без сессии: обновлять нечего, сеть не нагружается.
      await expectLater(
        repos.books.find(const BookQuery()),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(server.refreshCount, 1);
    });

    test('повторный 401 после успешного обновления не зацикливает запросы', () async {
      final repos = await makeRepositories(server, user: 'reader');

      server.rejectAllAccess = true;
      await expectLater(
        repos.books.find(const BookQuery()),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(server.refreshCount, 1);
      expect(server.calls('GET', '/books'), hasLength(2));
      expect(repos.auth.isAuthenticated, isFalse);
    });

    test('недоступный сервер при обновлении не разрывает сессию', () async {
      final repos = await makeRepositories(server, user: 'reader');

      server.expireAccess();
      server.refreshUnreachable = true;
      await expectLater(
        repos.books.find(const BookQuery()),
        throwsA(isA<NetworkException>()),
      );

      expect(repos.auth.isAuthenticated, isTrue, reason: 'сеть могла просто пропасть');
      server.refreshUnreachable = false;
      final page = await repos.books.find(const BookQuery());
      expect(page.items, isNotEmpty);
    });
  });

  group('Ошибка входа', () {
    test('401 при неверном пароле не запускает обновление токена и не зацикливается', () async {
      final repos = await makeRepositories(server, user: null);

      await expectLater(
        repos.auth.login('reader', 'не тот'),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(server.loginCount, 1);
      expect(server.refreshCount, 0);
      expect(server.requests, hasLength(1));
    });
  });

  group('Ответ 403', () {
    test('превращается в понятное сообщение с названием нужной роли', () async {
      final repos = await makeRepositories(server, user: 'reader');

      await expectLater(
        repos.genres.create(const Genre(id: 0, name: 'Детектив')),
        throwsA(
          isA<ForbiddenException>().having(
            (e) => e.message,
            'сообщение',
            allOf(contains('Недостаточно прав'), contains('librarian')),
          ),
        ),
      );
    });

    test('не считается проблемой сессии: пользователь остаётся в системе', () async {
      final repos = await makeRepositories(server, user: 'reader');

      await expectLater(
        repos.genres.create(const Genre(id: 0, name: 'Детектив')),
        throwsA(isA<ForbiddenException>()),
      );

      expect(repos.auth.isAuthenticated, isTrue);
      expect(server.refreshCount, 0);
    });
  });

  test('AppRepositories.invalidateAll сбрасывает кэш справочников', () async {
    final AppRepositories repos = await makeRepositories(server, user: 'admin');

    await repos.genres.findAll();
    await repos.genres.findAll();
    expect(server.calls('GET', '/genres'), hasLength(1));

    repos.invalidateAll();
    await repos.genres.findAll();
    expect(server.calls('GET', '/genres'), hasLength(2));
  });
}
