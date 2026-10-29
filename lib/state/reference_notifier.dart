import 'package:flutter/foundation.dart';

import '../models/author.dart';
import '../models/book.dart';
import '../models/genre.dart';
import '../models/named_option.dart';
import '../models/publisher.dart';
import '../models/reader.dart';
import '../repositories/author_repository.dart';
import '../repositories/book_repository.dart';
import '../repositories/entity_repository.dart';
import 'paged_list_notifier.dart';

const String kDeletedSuffix = ' (удалено)';

class ReferenceNotifier extends ChangeNotifier {
  ReferenceNotifier({
    required GenreRepository genres,
    required PublisherRepository publishers,
    required AuthorRepository authors,
    required BookRepository books,
    required ReaderRepository readers,
    bool loadReaders = true,
  })  : _loadReaders = loadReaders,
        _genres = genres,
        _publishers = publishers,
        _authors = authors,
        _books = books,
        _readers = readers;

  final GenreRepository _genres;
  final PublisherRepository _publishers;
  final AuthorRepository _authors;
  final BookRepository _books;
  final ReaderRepository _readers;

  /// Читателю список читателей не нужен и не должен запрашиваться.
  final bool _loadReaders;

  Map<int, String> _genreNames = const {};
  Map<int, String> _publisherNames = const {};
  Map<int, String> _authorNames = const {};
  Map<int, String> _readerNames = const {};
  Map<int, ({String title, int free})> _bookInfo = const {};
  Set<int> _deletedGenres = const {};
  Set<int> _deletedPublishers = const {};
  Set<int> _deletedAuthors = const {};
  Set<int> _deletedReaders = const {};
  Set<int> _deletedBooks = const {};
  Map<int, Set<int>> _authorsByPublisher = const {};
  bool _ready = false;
  bool _failed = false;
  String? _error;
  bool _disposed = false;

  bool get ready => _ready;
  bool get failed => _failed;
  String? get error => _error;

  String genreName(int id) => _label(_genreNames, _deletedGenres, id, '—');
  String publisherName(int id) =>
      _label(_publisherNames, _deletedPublishers, id, '—');
  String authorName(int id) =>
      _label(_authorNames, _deletedAuthors, id, 'Неизвестный автор');

  String genreNames(List<int> ids) => ids.map(genreName).join(', ');
  String authorNames(List<int> ids) => ids.map(authorName).join(', ');

  List<NamedOption> genreOptions({Iterable<int> keep = const []}) =>
      _options(_genreNames, _deletedGenres, keep);

  List<NamedOption> publisherOptions({Iterable<int> keep = const []}) =>
      _options(_publisherNames, _deletedPublishers, keep);

  List<NamedOption> authorOptions({Iterable<int> keep = const []}) =>
      _options(_authorNames, _deletedAuthors, keep);

  List<NamedOption> readerOptions({Iterable<int> keep = const []}) =>
      _options(_readerNames, _deletedReaders, keep);

  List<NamedOption> bookOptions({Iterable<int> keep = const []}) {
    final titles = {
      for (final entry in _bookInfo.entries)
        entry.key: '${entry.value.title} (свободно: ${entry.value.free})',
    };
    return _options(titles, _deletedBooks, keep);
  }

  List<NamedOption> authorOptionsForPublisher(
    int? publisherId, {
    Iterable<int> keep = const [],
  }) {
    final ids = publisherId == null ? null : _authorsByPublisher[publisherId];
    if (ids == null || ids.isEmpty) return const [];
    return _options(_authorNames, _deletedAuthors, keep)
        .where((o) => ids.contains(o.id) || keep.contains(o.id))
        .toList();
  }

  Future<void> load({bool withLinks = false}) async {
    try {
      final base = await Future.wait<Object?>([
        _genres.findAll(),
        _publishers.findAll(),
        _authors.findAll(),
      ]);
      final genres = base[0] as List<Genre>;
      final publishers = base[1] as List<Publisher>;
      final authors = base[2] as List<Author>;

      _genreNames = {for (final g in genres) g.id: g.name};
      _publisherNames = {for (final p in publishers) p.id: p.name};
      _authorNames = {for (final a in authors) a.id: a.fullName};
      _deletedGenres = {for (final g in genres) if (g.isDeleted) g.id};
      _deletedPublishers = {for (final p in publishers) if (p.isDeleted) p.id};
      _deletedAuthors = {for (final a in authors) if (a.isDeleted) a.id};

      if (withLinks) {
        final links = await Future.wait<Object?>([
          _books.findAll(),
          if (_loadReaders) _readers.findAll() else Future<List<Reader>>.value(const []),
        ]);
        final books = links[0] as List<Book>;
        final readers = links[1] as List<Reader>;

        final byPublisher = <int, Set<int>>{};
        for (final book in books) {
          if (book.isDeleted) continue;
          byPublisher
              .putIfAbsent(book.publisherId, () => <int>{})
              .addAll(book.authorIds);
        }
        _authorsByPublisher = byPublisher;
        _bookInfo = {
          for (final b in books) b.id: (title: b.title, free: b.copiesAvailable),
        };
        _deletedBooks = {for (final b in books) if (b.isDeleted) b.id};
        _readerNames = {for (final r in readers) r.id: r.fullName};
        _deletedReaders = {for (final r in readers) if (r.isDeleted) r.id};
      }

      _failed = false;
      _error = null;
      _ready = true;
    } catch (e) {
      _failed = true;
      _error = describeError(e);
    }
    notifyListeners();
  }

  String _label(Map<int, String> names, Set<int> deleted, int id, String fallback) {
    final name = names[id];
    if (name == null) return fallback;
    return deleted.contains(id) ? '$name$kDeletedSuffix' : name;
  }

  List<NamedOption> _options(
    Map<int, String> names,
    Set<int> deleted,
    Iterable<int> keep,
  ) {
    final keepSet = keep.toSet();
    final list = <NamedOption>[
      for (final entry in names.entries)
        if (!deleted.contains(entry.key) || keepSet.contains(entry.key))
          (
            id: entry.key,
            name: deleted.contains(entry.key)
                ? '${entry.value}$kDeletedSuffix'
                : entry.value,
          ),
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
