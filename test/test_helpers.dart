import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:library_app/app_repositories.dart';
import 'package:library_app/auth/auth_api.dart';
import 'package:library_app/auth/auth_notifier.dart';
import 'package:library_app/auth/session_policy.dart';
import 'package:library_app/core/api_client.dart';
import 'package:library_app/models/json_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Учётные записи тестового сервера (те же, что в учебном мок-сервере).
const Map<String, String> kTestPasswords = {
  'admin': 'admin123',
  'librarian': 'librarian123',
  'reader': 'reader123',
};

const Map<String, int> _roleLevel = {'reader': 1, 'librarian': 2, 'admin': 3};

class FakeUser {
  FakeUser(this.id, this.username, this.password, this.fullName, this.role, {this.readerId});

  final int id;
  final String username;
  final String password;
  final String fullName;
  String role;
  final int? readerId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'fullName': fullName,
        'email': '$username@example.com',
        'role': role,
        'readerId': readerId,
      };
}

class FakeServer implements HttpClientAdapter {
  FakeServer() {
    reset();
  }

  final List<RequestOptions> requests = [];
  bool down = false;
  bool malformed = false;
  Duration delay = Duration.zero;

  late Map<String, List<Map<String, dynamic>>> data;
  int _nextId = 100;
  int _issued = 0;

  /// Пользователи сервера. Роль берётся отсюда, а не из токена: как на настоящем сервере.
  late List<FakeUser> users;
  final Map<String, int> _access = {};
  final Map<String, int> _refresh = {};

  /// Сервер отвечает 401 на любое обновление токена.
  bool refreshRejected = false;

  /// Сервер не принимает ни один токен доступа, даже свежий.
  bool rejectAllAccess = false;

  /// Сервер недоступен только для запроса обновления токена.
  bool refreshUnreachable = false;

  /// Пауза внутри обновления токена (чтобы параллельные запросы успели встать в очередь).
  Duration refreshDelay = Duration.zero;

  void reset() {
    users = [
      FakeUser(1, 'admin', 'admin123', 'Администратор', 'admin'),
      FakeUser(2, 'librarian', 'librarian123', 'Петрова А. С.', 'librarian'),
      FakeUser(3, 'reader', 'reader123', 'Смирнов П. А.', 'reader', readerId: 1),
    ];
    _access.clear();
    _refresh.clear();
    data = {
      'genres': [
        {'id': 1, 'name': 'Роман', 'description': 'Крупная форма', 'deletedAt': null},
        {'id': 2, 'name': 'Фантастика', 'description': '', 'deletedAt': null},
      ],
      'publishers': [
        {'id': 1, 'name': 'Азбука', 'city': 'Санкт-Петербург', 'foundedYear': 1995, 'deletedAt': null},
        {'id': 2, 'name': 'Эксмо', 'city': 'Москва', 'foundedYear': 1991, 'deletedAt': null},
        {'id': 3, 'name': 'Питер', 'city': 'Санкт-Петербург', 'foundedYear': 1991, 'deletedAt': null},
      ],
      'authors': [
        {'id': 1, 'fullName': 'Достоевский Ф. М.', 'birthYear': 1821, 'country': 'Россия', 'deletedAt': null},
        {'id': 2, 'fullName': 'Оруэлл Дж.', 'birthYear': 1903, 'country': 'Великобритания', 'deletedAt': null},
      ],
      'books': [
        _book(1, 'Идиот', '978-5-389-07773-7', 1869, 1, [1], [1], 2, 2),
        _book(2, 'Преступление и наказание', '978-5-389-06003-6', 1866, 1, [1], [1], 5, 5),
        _book(3, '1984', '978-5-17-080115-5', 1949, 2, [2], [2], 5, 0),
        _book(4, 'Скотный двор', '978-5-17-097584-1', 1945, 2, [2], [2], 3, 3),
      ],
      'readers': [
        {
          'id': 1,
          'fullName': 'Смирнов П. А.',
          'email': 'smirnov@example.com',
          'phone': '+7 900 100-10-01',
          'card': {
            'id': 1,
            'number': 'RC-000001',
            'issuedAt': '2026-01-15T00:00:00.000Z',
            'expiresAt': '2027-01-15T00:00:00.000Z',
          },
          'deletedAt': null,
        },
        {
          'id': 2,
          'fullName': 'Кузнецова М. И.',
          'email': 'kuznetsova@example.com',
          'phone': '',
          'card': null,
          'deletedAt': null,
        },
      ],
      'loans': [
        {
          'id': 1,
          'reader': {'id': 1, 'fullName': 'Смирнов П. А.'},
          'book': {'id': 3, 'title': '1984'},
          'issuedAt': '2026-10-01T10:00:00.000Z',
          'dueAt': '2026-10-15T10:00:00.000Z',
          'returnedAt': null,
          'status': 'overdue',
          'deletedAt': null,
        },
        {
          'id': 2,
          'reader': {'id': 2, 'fullName': 'Кузнецова М. И.'},
          'book': {'id': 2, 'title': 'Преступление и наказание'},
          'issuedAt': '2026-10-20T10:00:00.000Z',
          'dueAt': '2026-11-20T10:00:00.000Z',
          'returnedAt': null,
          'status': 'active',
          'deletedAt': null,
        },
        {
          'id': 3,
          'reader': {'id': 1, 'fullName': 'Смирнов П. А.'},
          'book': {'id': 4, 'title': 'Скотный двор'},
          'issuedAt': '2026-10-25T10:00:00.000Z',
          'dueAt': '2026-11-25T10:00:00.000Z',
          'returnedAt': null,
          'status': 'active',
          'deletedAt': null,
        },
      ],
    };
  }

  Map<String, dynamic> _book(
    int id,
    String title,
    String isbn,
    int year,
    int publisherId,
    List<int> authorIds,
    List<int> genreIds,
    int total,
    int available,
  ) {
    return {
      'id': id,
      'title': title,
      'isbn': isbn,
      'year': year,
      'pages': 300,
      'publisher': {'id': publisherId, 'name': 'Издательство $publisherId'},
      'authors': [for (final a in authorIds) {'id': a, 'fullName': 'Автор $a'}],
      'genres': [for (final g in genreIds) {'id': g, 'name': 'Жанр $g'}],
      'copiesTotal': total,
      'copiesAvailable': available,
      'deletedAt': null,
    };
  }

  /// Токены доступа перестали действовать (прошёл срок --ttl).
  void expireAccess() => _access.clear();

  /// Токены обновления больше не принимаются.
  void expireRefresh() => _refresh.clear();

  int get loginCount => requests.where((r) => r.uri.path.endsWith('/auth/login')).length;

  int get refreshCount => requests.where((r) => r.uri.path.endsWith('/auth/refresh')).length;

  Iterable<RequestOptions> get protectedCalls =>
      requests.where((r) => !r.uri.path.contains('/auth/'));

  FakeUser? _userOf(RequestOptions options) {
    if (rejectAllAccess) return null;
    final header = '${options.headers['Authorization'] ?? ''}';
    if (!header.startsWith('Bearer ')) return null;
    final id = _access[header.substring(7)];
    if (id == null) return null;
    for (final user in users) {
      if (user.id == id) return user;
    }
    return null;
  }

  Map<String, dynamic> _tokens(FakeUser user) {
    final n = ++_issued;
    final access = 'access-$n-${user.id}';
    final refresh = 'refresh-$n-${user.id}';
    _access[access] = user.id;
    _refresh[refresh] = user.id;
    return {
      'accessToken': access,
      'refreshToken': refresh,
      'expiresIn': 900,
      'user': user.toJson(),
    };
  }

  Iterable<RequestOptions> calls(String method, String path) =>
      requests.where((r) => r.method == method && r.uri.path == '/api$path');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    if (delay > Duration.zero) {
      final cancelled = cancelFuture?.then((_) => true) ?? Completer<bool>().future;
      final finished = Future<bool>.delayed(delay, () => false);
      if (await Future.any([cancelled, finished])) {
        throw DioException.requestCancelled(requestOptions: options, reason: 'cancel');
      }
    }

    if (down) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      );
    }
    return _route(options);
  }

  @override
  void close({bool force = false}) {}

  ResponseBody _json(int status, Object? body) {
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  ResponseBody _fail(int status, String message) =>
      _json(status, {'message': message});

  Future<ResponseBody> _route(RequestOptions options) async {
    final method = options.method.toUpperCase();
    final query = options.uri.queryParameters;
    final path = options.uri.path.replaceFirst('/api', '');
    final body = options.data is Map
        ? Map<String, dynamic>.from(options.data as Map)
        : <String, dynamic>{};

    if (query.containsKey('__fail')) {
      return _fail(int.parse(query['__fail']!), 'Ошибка вызвана намеренно');
    }

    if (path.startsWith('/auth/')) {
      if (path == '/auth/refresh' && refreshDelay > Duration.zero) {
        await Future<void>.delayed(refreshDelay);
      }
      return _auth(options, path, method, body);
    }

    final current = _userOf(options);
    if (current == null) return _fail(401, 'Требуется аутентификация');

    if (path == '/users' && method == 'GET') {
      if (!_atLeast(current, 'admin')) return _forbidden('admin');
      return _json(200, {
        'items': [for (final u in users) u.toJson()],
        'page': 1,
        'size': 10,
        'total': users.length,
        'totalPages': 1,
      });
    }
    final userMatch = RegExp(r'^/users/(\d+)$').firstMatch(path);
    if (userMatch != null && method == 'PATCH') {
      if (!_atLeast(current, 'admin')) return _forbidden('admin');
      final target = users.where((u) => u.id == int.parse(userMatch.group(1)!));
      if (target.isEmpty) return _fail(404, 'Пользователь не найден');
      final role = '${body['role']}';
      if (!_roleLevel.containsKey(role)) {
        return _json(422, {
          'message': 'Ошибка валидации',
          'errors': {'role': 'Допустимые роли: reader, librarian, admin'},
        });
      }
      target.first.role = role;
      return _json(200, target.first.toJson());
    }

    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty || !data.containsKey(parts[0])) {
      return _fail(404, 'Адрес не обслуживается');
    }
    final collection = parts[0];
    final rows = data[collection]!;

    final denied = _checkRole(current, method, parts, query);
    if (denied != null) return denied;

    if (method == 'GET' && parts.length == 1) {
      if (malformed) return _json(200, {'oops': 1});
      var visible = rows;
      if (current.role == 'reader' && collection == 'loans') {
        visible = [for (final r in rows) if (jsonRefId(r['reader']) == current.readerId) r];
      }
      if (current.role == 'reader' && collection == 'readers') {
        visible = [for (final r in rows) if (r['id'] == current.readerId) r];
      }
      return _json(200, _list(collection, visible, query));
    }

    if (method == 'GET' && parts.length == 2) {
      final row = _find(rows, int.parse(parts[1]));
      return row == null ? _fail(404, 'Объект не найден') : _json(200, row);
    }

    if (method == 'POST' && collection == 'loans' && parts.length == 1) {
      return _issueLoan(body);
    }

    if (method == 'POST' && parts.length == 2 && parts[1] == 'bulk-delete') {
      final ids = (body['ids'] as List).cast<int>();
      var deleted = 0;
      for (final row in rows) {
        if (ids.contains(row['id']) && row['deletedAt'] == null) {
          row['deletedAt'] = DateTime.now().toIso8601String();
          deleted++;
        }
      }
      return _json(200, {'deleted': deleted});
    }

    if (method == 'POST' && collection == 'loans' && parts.length == 3 && parts[2] == 'extend') {
      final row = _find(rows, int.parse(parts[1]));
      if (row == null) return _fail(404, 'Выдача не найдена');
      if (current.role == 'reader' && jsonRefId(row['reader']) != current.readerId) {
        return _fail(403, 'Продлевать можно только собственные выдачи');
      }
      if (row['returnedAt'] != null) return _fail(409, 'Выдача уже закрыта');
      row['dueAt'] = '2026-12-31T10:00:00.000Z';
      return _json(200, row);
    }

    if (method == 'POST' && parts.length == 3) {
      final row = _find(rows, int.parse(parts[1]));
      if (row == null) return _fail(404, 'Объект не найден');
      if (parts[2] == 'restore') row['deletedAt'] = null;
      if (parts[2] == 'return') row['returnedAt'] = DateTime.now().toIso8601String();
      return _json(200, row);
    }

    if (method == 'POST' && parts.length == 1) {
      final errors = _validate(collection, body, null);
      if (errors.isNotEmpty) {
        return _json(422, {'message': 'Ошибка валидации', 'errors': errors});
      }
      final row = {...body, 'id': _nextId++, 'deletedAt': null};
      rows.add(row);
      return _json(201, row);
    }

    if (method == 'PUT' && parts.length == 2) {
      final id = int.parse(parts[1]);
      final row = _find(rows, id);
      if (row == null) return _fail(404, 'Объект не найден');
      final errors = _validate(collection, body, id);
      if (errors.isNotEmpty) {
        return _json(422, {'message': 'Ошибка валидации', 'errors': errors});
      }
      row.addAll(body);
      if (collection == 'books') {
        row
          ..remove('publisher')
          ..remove('authors')
          ..remove('genres');
      }
      return _json(200, row);
    }

    if (method == 'DELETE' && parts.length == 2) {
      final id = int.parse(parts[1]);
      final row = _find(rows, id);
      if (row == null) return _fail(404, 'Объект не найден');
      if (query['hard'] == 'true') {
        rows.remove(row);
      } else {
        row['deletedAt'] = DateTime.now().toIso8601String();
      }
      return _json(204, null);
    }

    return _fail(404, 'Адрес не обслуживается');
  }

  bool _atLeast(FakeUser user, String role) => _roleLevel[user.role]! >= _roleLevel[role]!;

  ResponseBody _forbidden(String role) =>
      _fail(403, 'Операция доступна начиная с роли «$role»');

  /// Права как в КОНТРАКТ-API.md, раздел 2.2.
  ResponseBody? _checkRole(
    FakeUser user,
    String method,
    List<String> parts,
    Map<String, String> query,
  ) {
    if (method == 'GET') return null;
    final last = parts.isEmpty ? '' : parts.last;
    if (last == 'extend') return null;
    final adminOnly = last == 'restore' || (method == 'DELETE' && query['hard'] == 'true');
    final needed = adminOnly ? 'admin' : 'librarian';
    return _atLeast(user, needed) ? null : _forbidden(needed);
  }

  ResponseBody _auth(
    RequestOptions options,
    String path,
    String method,
    Map<String, dynamic> body,
  ) {
    if (path == '/auth/login' && method == 'POST') {
      for (final user in users) {
        if (user.username == '${body['username']}' && user.password == '${body['password']}') {
          return _json(200, _tokens(user));
        }
      }
      return _fail(401, 'Неверный логин или пароль');
    }

    if (path == '/auth/refresh' && method == 'POST') {
      if (refreshUnreachable) {
        throw DioException.connectionError(requestOptions: options, reason: 'Connection refused');
      }
      if (refreshRejected) return _fail(401, 'Токен обновления недействителен');
      final id = _refresh.remove('${body['refreshToken']}');
      if (id == null) return _fail(401, 'Токен обновления недействителен');
      return _json(200, _tokens(users.firstWhere((u) => u.id == id)));
    }

    if (path == '/auth/me' && method == 'GET') {
      final user = _userOf(options);
      return user == null ? _fail(401, 'Требуется аутентификация') : _json(200, user.toJson());
    }

    if (path == '/auth/logout' && method == 'POST') {
      _refresh.remove('${body['refreshToken']}');
      return _json(204, null);
    }

    if (path == '/auth/register' && method == 'POST') {
      final errors = <String, String>{};
      final username = '${body['username']}'.trim();
      final password = '${body['password']}';
      if (username.length < 3) {
        errors['username'] = 'Логин не короче трёх символов';
      } else if (users.any((u) => u.username == username)) {
        errors['username'] = 'Такой логин уже занят';
      }
      if (password.length < 8) {
        errors['password'] = 'Пароль не короче восьми символов';
      } else if (!RegExp(r'\d').hasMatch(password)) {
        errors['password'] = 'Пароль должен содержать цифру';
      }
      if (errors.isNotEmpty) {
        return _json(422, {'message': 'Ошибка валидации', 'errors': errors});
      }
      final user = FakeUser(
        users.length + 1,
        username,
        password,
        '${body['fullName'] ?? username}',
        'reader',
      );
      users.add(user);
      return _json(201, user.toJson());
    }

    return _fail(404, 'Адрес не обслуживается');
  }

  int _bounded(int value, int low, int high) =>
      value < low ? low : (value > high ? high : value);

  Map<String, dynamic>? _find(List<Map<String, dynamic>> rows, int id) {
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  ResponseBody _issueLoan(Map<String, dynamic> body) {
    final book = _find(data['books']!, jsonInt(body['bookId']));
    final reader = _find(data['readers']!, jsonInt(body['readerId']));
    if (book == null || reader == null) {
      return _json(422, {
        'message': 'Ошибка валидации',
        'errors': {
          if (reader == null) 'readerId': 'Читатель не найден',
          if (book == null) 'bookId': 'Книга не найдена',
        },
      });
    }
    if (jsonInt(book['copiesAvailable']) < 1) {
      return _fail(409, 'Нет свободных экземпляров этой книги');
    }
    book['copiesAvailable'] = jsonInt(book['copiesAvailable']) - 1;
    final loan = {
      'id': _nextId++,
      'reader': {'id': reader['id'], 'fullName': reader['fullName']},
      'book': {'id': book['id'], 'title': book['title']},
      'issuedAt': DateTime.now().toIso8601String(),
      'dueAt': DateTime.now().add(const Duration(days: 14)).toIso8601String(),
      'returnedAt': null,
      'status': 'active',
      'deletedAt': null,
    };
    data['loans']!.add(loan);
    return _json(201, loan);
  }

  Map<String, String> _validate(String collection, Map<String, dynamic> body, int? id) {
    if (collection == 'books') {
      final duplicate = data['books']!.any(
        (b) => b['isbn'] == body['isbn'] && b['id'] != id && b['deletedAt'] == null,
      );
      if (duplicate) return {'isbn': 'Книга с таким ISBN уже существует'};
    }
    if (collection == 'genres') {
      final name = '${body['name']}'.toLowerCase();
      final duplicate = data['genres']!.any(
        (g) => '${g['name']}'.toLowerCase() == name && g['id'] != id && g['deletedAt'] == null,
      );
      if (duplicate) return {'name': 'Такой жанр уже существует'};
    }
    return const {};
  }

  Map<String, dynamic> _list(
    String collection,
    List<Map<String, dynamic>> source,
    Map<String, String> query,
  ) {
    var rows = source.where((r) => query['includeDeleted'] == 'true' || r['deletedAt'] == null).toList();

    final needle = (query['search'] ?? '').toLowerCase();
    if (needle.isNotEmpty) {
      rows = rows
          .where((r) => r.values.whereType<String>().join(' ').toLowerCase().contains(needle))
          .toList();
    }

    if (collection == 'books') {
      int? number(String key) => int.tryParse(query[key] ?? '');
      final genreId = number('genreId');
      final publisherId = number('publisherId');
      final authorId = number('authorId');
      final from = number('yearFrom');
      final to = number('yearTo');
      rows = rows.where((b) {
        if (genreId != null && !jsonRefIds(b['genres']).contains(genreId)) return false;
        if (authorId != null && !jsonRefIds(b['authors']).contains(authorId)) return false;
        if (publisherId != null && jsonRefId(b['publisher']) != publisherId) return false;
        if (from != null && jsonInt(b['year']) < from) return false;
        if (to != null && jsonInt(b['year']) > to) return false;
        if (query['available'] == 'true' && jsonInt(b['copiesAvailable']) < 1) return false;
        return true;
      }).toList();
    }

    if (collection == 'loans' && (query['status'] ?? '').isNotEmpty) {
      rows = rows.where((l) => l['status'] == query['status']).toList();
    }

    final sort = (query['sort'] ?? '').split(',');
    if (sort.first.isNotEmpty) {
      final direction = sort.length > 1 && sort[1] == 'desc' ? -1 : 1;
      rows.sort((a, b) {
        final left = a[sort.first];
        final right = b[sort.first];
        if (left is num && right is num) return left.compareTo(right) * direction;
        return '$left'.toLowerCase().compareTo('$right'.toLowerCase()) * direction;
      });
    }

    final size = _bounded(int.tryParse(query['size'] ?? '') ?? 10, 1, 100);
    final page = _bounded(int.tryParse(query['page'] ?? '') ?? 1, 1, 1000000);
    final total = rows.length;
    final from = (page - 1) * size;
    final end = from + size > total ? total : from + size;
    final items = from >= total ? <Map<String, dynamic>>[] : rows.sublist(from, end);

    return {
      'items': items,
      'page': page,
      'size': size,
      'total': total,
      'totalPages': total == 0 ? 1 : (total / size).ceil(),
    };
  }
}

/// Собирает клиент поверх тестового сервера. По умолчанию входит под [user]
/// (admin, librarian, reader); null: оставляет клиент без входа.
Future<AppRepositories> makeRepositories(
  FakeServer server, {
  String? user = 'admin',
  Map<String, String> debugFlags = const {},
  SessionPolicy policy = const SessionPolicy(),
  DateTime Function()? now,
  SharedPreferences? prefs,
}) async {
  SharedPreferences store;
  if (prefs != null) {
    store = prefs;
  } else {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
  }
  final auth = AuthNotifier(
    prefs: store,
    api: AuthApi(buildAuthDio(adapter: server)),
    policy: policy,
    now: now,
  );
  final dio = buildDio(
    auth: auth,
    adapter: server,
    retryDelays: const [Duration.zero, Duration.zero],
    debugFlags: debugFlags,
  );
  final repositories = AppRepositories(dio: dio, auth: auth);
  if (user != null) await auth.login(user, kTestPasswords[user]!);
  return repositories;
}

/// Клиент с уже подготовленной парой токенов, но без входа через форму.
Future<AuthNotifier> makeAuth(
  FakeServer server,
  SharedPreferences prefs, {
  SessionPolicy policy = const SessionPolicy(),
  DateTime Function()? now,
}) async {
  return AuthNotifier(
    prefs: prefs,
    api: AuthApi(buildAuthDio(adapter: server)),
    policy: policy,
    now: now,
  );
}
