import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/app_repositories.dart';
import 'package:library_app/core/api_exceptions.dart';
import 'package:library_app/models/author.dart';
import 'package:library_app/models/author_query.dart';
import 'package:library_app/models/book.dart';
import 'package:library_app/models/book_query.dart';
import 'package:library_app/models/genre.dart';
import 'package:library_app/models/simple_query.dart';

import 'test_helpers.dart';

Book _draft({String isbn = '978-5-00-000001-0', String title = 'Новая книга'}) {
  return Book(
    id: 0,
    title: title,
    isbn: isbn,
    year: 2020,
    pages: 100,
    publisherId: 1,
    authorIds: const [1],
    genreIds: const [1],
    copiesTotal: 3,
  );
}

SimpleQuery _genreQuery() =>
    SimpleQuery.initial(sortFields: kGenreSortFields, defaultSort: 'name');

void main() {
  late FakeServer server;
  late AppRepositories repos;

  setUp(() async {
    server = FakeServer();
    repos = await makeRepositories(server);
  });

  test('Список запрашивается с параметрами поиска, фильтра, сортировки и страницы', () async {
    final page = await repos.books.find(
      const BookQuery(
        search: 'идиот',
        genreId: 1,
        sortField: 'year',
        sortAscending: false,
        page: 2,
        size: 25,
      ),
    );

    final request = server.calls('GET', '/books').single;
    expect(request.uri.queryParameters, {
      'search': 'идиот',
      'sort': 'year,desc',
      'page': '2',
      'size': '25',
      'genreId': '1',
    });
    expect(page.page, 2);
    expect(page.items, isEmpty);
    expect(page.total, 1);
  });

  test('Ответ сервера разбирается в страницу с развёрнутыми связями книги', () async {
    final page = await repos.books.find(const BookQuery());

    expect(page.total, 4);
    final book = page.items.firstWhere((b) => b.id == 1);
    expect(book.title, 'Идиот');
    expect(book.publisherId, 1);
    expect(book.authorIds, [1]);
    expect(book.genreIds, [1]);
    expect(book.copiesAvailable, 2);
  });

  test('Ошибка 422 превращается в исключение с сообщениями для полей формы', () async {
    await expectLater(
      repos.books.create(_draft(isbn: '978-5-389-07773-7')),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.errors,
          'ошибки по полям',
          {'isbn': 'Книга с таким ISBN уже существует'},
        ),
      ),
    );
  });

  test('Ошибка 409 при выдаче книги без свободных экземпляров становится ConflictException', () async {
    await expectLater(
      repos.loans.issue(readerId: 1, bookId: 3, days: 14),
      throwsA(
        isA<ConflictException>().having(
          (e) => e.message,
          'сообщение',
          'Нет свободных экземпляров этой книги',
        ),
      ),
    );
  });

  test('Недоступный сервер даёт NetworkException после трёх попыток чтения', () async {
    server.down = true;

    await expectLater(
      repos.books.find(const BookQuery()),
      throwsA(isA<NetworkException>()),
    );

    expect(server.calls('GET', '/books'), hasLength(3));
  });

  test('Запись не повторяется автоматически при сетевой ошибке', () async {
    await repos.books.create(_draft());
    server.requests.clear();
    server.down = true;

    await expectLater(
      repos.books.create(_draft(isbn: '978-5-00-000002-7')),
      throwsA(isA<NetworkException>()),
    );

    expect(server.calls('POST', '/books'), hasLength(1));
  });

  test('Ошибка 500 превращается в ServerException без повторов', () async {
    final failing = await makeRepositories(server, debugFlags: {'__fail': '500'});

    await expectLater(
      failing.books.find(const BookQuery()),
      throwsA(isA<ServerException>()),
    );

    expect(server.calls('GET', '/books'), hasLength(1));
  });

  test('Ответ в неожиданном формате не роняет приложение', () async {
    server.malformed = true;

    await expectLater(
      repos.books.find(const BookQuery()),
      throwsA(isA<ServerException>()),
    );
  });

  test('Несуществующая запись возвращается как null', () async {
    expect(await repos.books.findById(999), isNull);
    expect((await repos.books.findById(1))?.title, 'Идиот');
  });

  test('Справочник жанров кэшируется и сбрасывается после изменения', () async {
    final first = await repos.genres.findAll();
    final second = await repos.genres.findAll();

    expect(first, hasLength(2));
    expect(second, hasLength(2));
    expect(server.calls('GET', '/genres'), hasLength(1));

    await repos.genres.create(const Genre(id: 0, name: 'Детектив'));
    final third = await repos.genres.findAll();

    expect(third, hasLength(3));
    expect(server.calls('GET', '/genres'), hasLength(2));
  });

  test('Устаревший запрос списка отменяется новым', () async {
    server.delay = const Duration(milliseconds: 30);

    final stale = repos.books.find(const BookQuery(search: 'и'));
    final fresh = repos.books.find(const BookQuery(search: 'ск'));

    await expectLater(stale, throwsA(isA<CancelledException>()));
    final page = await fresh;
    expect(page.items, isNotEmpty);
  });

  test('Отладочные параметры добавляются к каждому запросу', () async {
    final slow = await makeRepositories(server, debugFlags: {'__delay': '1500'});

    await slow.authors.find(const AuthorQuery());

    expect(
      server.calls('GET', '/authors').single.uri.queryParameters['__delay'],
      '1500',
    );
  });

  test('Издательство с книгами нельзя удалить, запрос на удаление не отправляется', () async {
    await expectLater(
      repos.publishers.softDelete(1),
      throwsA(
        isA<ConflictException>().having(
          (e) => e.message,
          'сообщение',
          contains('у него есть книги (2)'),
        ),
      ),
    );

    expect(server.calls('DELETE', '/publishers/1'), isEmpty);
  });

  test('Полный цикл: создание, изменение, мягкое и физическое удаление, восстановление', () async {
    final created = await repos.authors.create(
      const Author(id: 0, fullName: 'Булгаков М. А.', country: 'Россия', birthYear: 1891),
    );
    expect(created.id, greaterThan(0));

    final changed = await repos.authors.update(created.copyWith(country: 'СССР'));
    expect(changed.country, 'СССР');

    await repos.authors.softDelete(created.id);
    expect((await repos.authors.findById(created.id))?.isDeleted, isTrue);

    await repos.authors.restore(created.id);
    expect((await repos.authors.findById(created.id))?.isDeleted, isFalse);

    await repos.authors.hardDelete(created.id);
    expect(await repos.authors.findById(created.id), isNull);
  });

  test('Множественное удаление возвращает число удалённых записей', () async {
    final deleted = await repos.books.deleteMany([1, 2]);

    expect(deleted, 2);
    expect((await repos.books.find(const BookQuery())).total, 2);
  });

  test('Ошибка Dio не выходит за пределы репозитория', () async {
    server.down = true;

    try {
      await repos.genres.find(_genreQuery());
      fail('Ожидалась ошибка');
    } on DioException {
      fail('DioException не должен попадать в вызывающий код');
    } on NetworkException catch (e) {
      expect(e.message, isNotEmpty);
    }
  });
}
