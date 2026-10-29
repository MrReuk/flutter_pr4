import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'app_repositories.dart';
import 'auth/auth_notifier.dart';
import 'auth/permissions.dart';
import 'models/author.dart';
import 'models/author_query.dart';
import 'models/book.dart';
import 'models/book_query.dart';
import 'models/genre.dart';
import 'models/loan.dart';
import 'models/publisher.dart';
import 'models/reader.dart';
import 'models/simple_query.dart';
import 'repositories/author_repository.dart';
import 'repositories/book_repository.dart';
import 'repositories/entity_repository.dart';
import 'repositories/stats_repository.dart';
import 'repositories/user_repository.dart';
import 'router.dart';
import 'state/paged_list_notifier.dart';
import 'state/reference_notifier.dart';
import 'widgets/session_guard.dart';

class LibraryApp extends StatefulWidget {
  const LibraryApp({
    super.key,
    required this.repositories,
    this.initialLocation = '/',
    this.clock,
  });

  final AppRepositories repositories;
  final String initialLocation;

  /// Часы для таймера сессии (в тестах подменяются).
  final DateTime Function()? clock;

  @override
  State<LibraryApp> createState() => _LibraryAppState();
}

class _LibraryAppState extends State<LibraryApp> {
  late final AuthNotifier _auth = widget.repositories.auth;
  late final GoRouter _router = buildRouter(
    auth: _auth,
    initialLocation: widget.initialLocation,
  );
  int? _userId;

  @override
  void initState() {
    super.initState();
    _userId = _auth.user?.id;
    _auth.addListener(_onAuthChanged);
  }

  /// Данные одного пользователя не должны достаться другому: при смене
  /// пользователя сбрасываем кэши репозиториев, а ниже по ключу пересоздаём
  /// все уведомители (списки, справочники).
  void _onAuthChanged() {
    final id = _auth.user?.id;
    if (id == _userId) return;
    _userId = id;
    widget.repositories.invalidateAll();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repos = widget.repositories;

    return MultiProvider(
      key: ValueKey<int?>(_userId),
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: _auth),
        Provider<UserRepository>.value(value: repos.users),
        Provider<StatsRepository>.value(value: repos.stats),
        Provider<BookRepository>.value(value: repos.books),
        Provider<AuthorRepository>.value(value: repos.authors),
        Provider<GenreRepository>.value(value: repos.genres),
        Provider<PublisherRepository>.value(value: repos.publishers),
        Provider<ReaderRepository>.value(value: repos.readers),
        Provider<LoanRepository>.value(value: repos.loans),
        ChangeNotifierProvider<PagedListNotifier<Book, BookQuery>>(
          create: (_) => PagedListNotifier<Book, BookQuery>(
            initialQuery: const BookQuery(),
            repository: repos.books,
            idOf: (book) => book.id,
          ),
        ),
        ChangeNotifierProvider<PagedListNotifier<Author, AuthorQuery>>(
          create: (_) => PagedListNotifier<Author, AuthorQuery>(
            initialQuery: const AuthorQuery(),
            repository: repos.authors,
            idOf: (author) => author.id,
          ),
        ),
        ChangeNotifierProvider<PagedListNotifier<Genre, SimpleQuery>>(
          create: (_) => PagedListNotifier<Genre, SimpleQuery>(
            initialQuery: SimpleQuery.initial(
              sortFields: kGenreSortFields,
              defaultSort: 'name',
            ),
            repository: repos.genres,
            idOf: (genre) => genre.id,
          ),
        ),
        ChangeNotifierProvider<PagedListNotifier<Publisher, SimpleQuery>>(
          create: (_) => PagedListNotifier<Publisher, SimpleQuery>(
            initialQuery: SimpleQuery.initial(
              sortFields: kPublisherSortFields,
              defaultSort: 'name',
            ),
            repository: repos.publishers,
            idOf: (publisher) => publisher.id,
          ),
        ),
        ChangeNotifierProvider<PagedListNotifier<Reader, SimpleQuery>>(
          create: (_) => PagedListNotifier<Reader, SimpleQuery>(
            initialQuery: SimpleQuery.initial(
              sortFields: kReaderSortFields,
              defaultSort: 'fullName',
            ),
            repository: repos.readers,
            idOf: (reader) => reader.id,
          ),
        ),
        ChangeNotifierProvider<PagedListNotifier<Loan, SimpleQuery>>(
          create: (_) => PagedListNotifier<Loan, SimpleQuery>(
            initialQuery: SimpleQuery.initial(
              sortFields: kLoanSortFields,
              defaultSort: 'issuedAt',
            ),
            repository: repos.loans,
            idOf: (loan) => loan.id,
          ),
        ),
        ChangeNotifierProvider<ReferenceNotifier>(
          create: (_) => ReferenceNotifier(
            genres: repos.genres,
            publishers: repos.publishers,
            authors: repos.authors,
            books: repos.books,
            readers: repos.readers,
            // Читателю список читателей не нужен и сервер его не отдаёт.
            loadReaders: _auth.can(Permission.viewReaders),
          )..load(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Библиотека',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        routerConfig: _router,
        builder: (context, child) => SessionGuard(
          now: widget.clock,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
