import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'auth/auth_notifier.dart';
import 'auth/route_access.dart';

import 'models/author.dart';
import 'models/author_query.dart';
import 'models/book.dart';
import 'models/book_query.dart';
import 'models/genre.dart';
import 'models/publisher.dart';
import 'models/reader.dart';
import 'models/simple_query.dart';
import 'repositories/author_repository.dart';
import 'repositories/book_repository.dart';
import 'repositories/entity_repository.dart';
import 'screens/author_detail_screen.dart';
import 'screens/author_form_screen.dart';
import 'screens/author_list_screen.dart';
import 'screens/book_detail_screen.dart';
import 'screens/book_form_screen.dart';
import 'screens/book_list_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/desk_screen.dart';
import 'screens/forbidden_screen.dart';
import 'screens/genre_detail_screen.dart';
import 'screens/genre_form_screen.dart';
import 'screens/genre_list_screen.dart';
import 'screens/loan_form_screen.dart';
import 'screens/loan_list_screen.dart';
import 'screens/login_screen.dart';
import 'screens/my_loans_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/offline_screen.dart';
import 'screens/publisher_detail_screen.dart';
import 'screens/publisher_form_screen.dart';
import 'screens/publisher_list_screen.dart';
import 'screens/reader_detail_screen.dart';
import 'screens/reader_form_screen.dart';
import 'screens/reader_list_screen.dart';
import 'screens/register_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/users_screen.dart';
import 'state/detail_notifier.dart';

int? _idFrom(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '');

GoRoute _entityRoute<T>({
  required String path,
  required Widget Function(GoRouterState state) list,
  required Widget Function(int? id) form,
  required Widget detail,
  required Future<T?> Function(int id) Function(BuildContext context) finder,
}) {
  return GoRoute(
    path: '/$path',
    builder: (context, state) => list(state),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) => form(null),
      ),
      GoRoute(
        path: ':id',
        builder: (context, state) {
          final id = _idFrom(state);
          if (id == null) return NotFoundScreen(location: state.uri.toString());
          return ChangeNotifierProvider<DetailNotifier<T>>(
            create: (context) {
              final find = finder(context);
              return DetailNotifier<T>(() => find(id))..load();
            },
            child: detail,
          );
        },
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) {
              final id = _idFrom(state);
              if (id == null) return NotFoundScreen(location: state.uri.toString());
              return form(id);
            },
          ),
        ],
      ),
    ],
  );
}

/// Решает, пускать ли на адрес. Вызывается при каждом переходе и при каждом
/// изменении состояния входа (refreshListenable), в том числе после выхода
/// по таймеру: открытый защищённый экран сразу заменяется на вход.
String? guardLocation(AuthNotifier auth, GoRouterState state) {
  final path = state.uri.path;
  final full = state.uri.toString();

  // Токены есть, но сервер недоступен: сессию не бросаем, ждём повтора.
  if (auth.isUnverified) return path == '/offline' ? null : '/offline';

  if (!auth.isAuthenticated) {
    if (isPublicPath(path)) return null;
    // Запоминаем, куда шёл пользователь, чтобы вернуть его после входа.
    final target = safeReturnTo(full);
    if (target == null || target == '/') return '/login';
    return '/login?from=${Uri.encodeComponent(target)}';
  }

  if (path == '/offline') return '/';
  if (isPublicPath(path)) {
    return safeReturnTo(state.uri.queryParameters['from']) ?? '/';
  }

  final needed = requiredPermission(full);
  if (needed != null && !auth.can(needed)) {
    return '/forbidden?path=${Uri.encodeComponent(full)}';
  }
  return null;
}

GoRouter buildRouter({required AuthNotifier auth, String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: auth,
    redirect: (context, state) => guardLocation(auth, state),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/offline',
        builder: (context, state) => const OfflineScreen(),
      ),
      GoRoute(
        path: '/forbidden',
        builder: (context, state) =>
            ForbiddenScreen(attempted: state.uri.queryParameters['path']),
      ),
      GoRoute(
        path: '/my/loans',
        builder: (context, state) => const MyLoansScreen(),
      ),
      GoRoute(
        path: '/desk',
        builder: (context, state) => const DeskScreen(),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const UsersScreen(),
      ),
      GoRoute(
        path: '/admin/stats',
        builder: (context, state) => const StatsScreen(),
      ),
      _entityRoute<Book>(
        path: 'books',
        list: (state) => BookListScreen(
          query: BookQuery.fromParams(state.uri.queryParameters),
        ),
        form: (id) => BookFormScreen(bookId: id),
        detail: const BookDetailScreen(),
        finder: (context) => context.read<BookRepository>().findById,
      ),
      _entityRoute<Author>(
        path: 'authors',
        list: (state) => AuthorListScreen(
          query: AuthorQuery.fromParams(state.uri.queryParameters),
        ),
        form: (id) => AuthorFormScreen(authorId: id),
        detail: const AuthorDetailScreen(),
        finder: (context) => context.read<AuthorRepository>().findById,
      ),
      _entityRoute<Genre>(
        path: 'genres',
        list: (state) => GenreListScreen(
          query: SimpleQuery.fromParams(
            state.uri.queryParameters,
            sortFields: kGenreSortFields,
            defaultSort: 'name',
          ),
        ),
        form: (id) => GenreFormScreen(genreId: id),
        detail: const GenreDetailScreen(),
        finder: (context) => context.read<GenreRepository>().findById,
      ),
      _entityRoute<Publisher>(
        path: 'publishers',
        list: (state) => PublisherListScreen(
          query: SimpleQuery.fromParams(
            state.uri.queryParameters,
            sortFields: kPublisherSortFields,
            defaultSort: 'name',
          ),
        ),
        form: (id) => PublisherFormScreen(publisherId: id),
        detail: const PublisherDetailScreen(),
        finder: (context) => context.read<PublisherRepository>().findById,
      ),
      _entityRoute<Reader>(
        path: 'readers',
        list: (state) => ReaderListScreen(
          query: SimpleQuery.fromParams(
            state.uri.queryParameters,
            sortFields: kReaderSortFields,
            defaultSort: 'fullName',
          ),
        ),
        form: (id) => ReaderFormScreen(readerId: id),
        detail: const ReaderDetailScreen(),
        finder: (context) => context.read<ReaderRepository>().findById,
      ),
      GoRoute(
        path: '/loans',
        builder: (context, state) => LoanListScreen(
          query: SimpleQuery.fromParams(
            state.uri.queryParameters,
            sortFields: kLoanSortFields,
            defaultSort: 'issuedAt',
          ),
        ),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const LoanFormScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => NotFoundScreen(location: state.uri.toString()),
  );
}
