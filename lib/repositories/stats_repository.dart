import 'package:dio/dio.dart';

import '../core/api_exceptions.dart';
import '../models/json_helpers.dart';

/// Сводка для администратора. Сервер не имеет отдельного адреса статистики,
/// поэтому числа собираются из обычных списков (size=1, нужен только total).
class LibraryStats {
  const LibraryStats({
    required this.books,
    required this.deletedBooks,
    required this.authors,
    required this.genres,
    required this.publishers,
    required this.readers,
    required this.activeLoans,
    required this.overdueLoans,
    required this.returnedLoans,
    required this.users,
  });

  final int books;
  final int deletedBooks;
  final int authors;
  final int genres;
  final int publishers;
  final int readers;
  final int activeLoans;
  final int overdueLoans;
  final int returnedLoans;
  final int users;

  int get loansTotal => activeLoans + overdueLoans + returnedLoans;
}

/// Счётчики выдач для главного экрана читателя и библиотекаря.
typedef LoanCounts = ({int active, int overdue});

abstract interface class StatsRepository {
  Future<LibraryStats> load();

  Future<LoanCounts> loanCounts();
}

class ApiStatsRepository implements StatsRepository {
  ApiStatsRepository({required this.dio});

  final Dio dio;

  Future<int> _total(String path, [Map<String, Object?> query = const {}]) async {
    final response = await dio.get<dynamic>(
      path,
      queryParameters: {'size': 1, ...query},
    );
    return jsonInt(jsonMap(response.data)['total']);
  }

  @override
  Future<LibraryStats> load() {
    return guard(() async {
      final r = await Future.wait<int>([
        _total('/books'),
        _total('/books', {'includeDeleted': 'true'}),
        _total('/authors'),
        _total('/genres'),
        _total('/publishers'),
        _total('/readers'),
        _total('/loans', {'status': 'active'}),
        _total('/loans', {'status': 'overdue'}),
        _total('/loans', {'status': 'returned'}),
        _total('/users'),
      ]);
      return LibraryStats(
        books: r[0],
        deletedBooks: r[1] - r[0],
        authors: r[2],
        genres: r[3],
        publishers: r[4],
        readers: r[5],
        activeLoans: r[6],
        overdueLoans: r[7],
        returnedLoans: r[8],
        users: r[9],
      );
    });
  }

  @override
  Future<LoanCounts> loanCounts() {
    return guard(() async {
      final r = await Future.wait<int>([
        _total('/loans', {'status': 'active'}),
        _total('/loans', {'status': 'overdue'}),
      ]);
      return (active: r[0], overdue: r[1]);
    });
  }
}
