import '../models/genre.dart';
import '../models/loan.dart';
import '../models/page_result.dart';
import '../models/publisher.dart';
import '../models/reader.dart';
import '../models/simple_query.dart';

abstract interface class EntityRepository<T, Q> {
  Future<PageResult<T>> find(Q query);
  Future<List<T>> findAll();
  Future<T?> findById(int id);
  Future<T> create(T item);
  Future<T> update(T item);
  Future<void> softDelete(int id);
  Future<void> hardDelete(int id);
  Future<void> restore(int id);
  Future<int> deleteMany(List<int> ids);
}

abstract interface class CachedRepository {
  void invalidate();
}

typedef GenreRepository = EntityRepository<Genre, SimpleQuery>;
typedef PublisherRepository = EntityRepository<Publisher, SimpleQuery>;
typedef ReaderRepository = EntityRepository<Reader, SimpleQuery>;

abstract interface class LoanRepository implements EntityRepository<Loan, SimpleQuery> {
  Future<Loan> issue({
    required int readerId,
    required int bookId,
    required int days,
  });

  Future<Loan> markReturned(int id);

  /// Продление срока выдачи читателем. Нужен сервер с адресом /loans/{id}/extend.
  Future<Loan> extend(int id);
}
