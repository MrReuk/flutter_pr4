import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_api.dart';
import 'auth/auth_notifier.dart';
import 'auth/session_policy.dart';
import 'core/api_client.dart';
import 'repositories/api_author_repository.dart';
import 'repositories/api_book_repository.dart';
import 'repositories/api_genre_repository.dart';
import 'repositories/api_loan_repository.dart';
import 'repositories/api_publisher_repository.dart';
import 'repositories/api_reader_repository.dart';
import 'repositories/entity_repository.dart';
import 'repositories/api_user_repository.dart';
import 'repositories/stats_repository.dart';
import 'repositories/user_repository.dart';

class AppRepositories {
  AppRepositories({required Dio dio, required this.auth}) {
    books = ApiBookRepository(dio: dio);
    authors = ApiAuthorRepository(dio: dio, books: books);
    genres = ApiGenreRepository(dio: dio, books: books);
    publishers = ApiPublisherRepository(dio: dio, books: books);
    readers = ApiReaderRepository(dio: dio);
    loans = ApiLoanRepository(dio: dio);
    users = ApiUserRepository(dio: dio);
    stats = ApiStatsRepository(dio: dio);
  }

  /// Собирает клиент: отдельный Dio для /auth/*, состояние входа и основной
  /// Dio, который берёт токен у состояния входа и сам обновляет его при 401.
  factory AppRepositories.connect({
    required SharedPreferences prefs,
    SessionPolicy policy = const SessionPolicy(),
    Map<String, String> debugFlags = const {},
  }) {
    final auth = AuthNotifier(
      prefs: prefs,
      api: AuthApi(buildAuthDio()),
      policy: policy,
    );
    return AppRepositories(
      dio: buildDio(auth: auth, debugFlags: debugFlags),
      auth: auth,
    );
  }

  final AuthNotifier auth;

  late final ApiBookRepository books;
  late final ApiAuthorRepository authors;
  late final ApiGenreRepository genres;
  late final ApiPublisherRepository publishers;
  late final ApiReaderRepository readers;
  late final ApiLoanRepository loans;
  late final UserRepository users;
  late final StatsRepository stats;

  /// Сбрасывает кэши справочников. Нужен при смене пользователя: данные,
  /// загруженные под одной ролью, не должны показываться другой.
  void invalidateAll() {
    for (final repository in <CachedRepository>[
      books,
      authors,
      genres,
      publishers,
      readers,
      loans,
    ]) {
      repository.invalidate();
    }
  }
}
