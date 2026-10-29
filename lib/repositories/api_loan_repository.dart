import 'package:dio/dio.dart';

import '../core/api_exceptions.dart';
import '../models/json_helpers.dart';
import '../models/loan.dart';
import '../models/simple_query.dart';
import 'api_repository.dart';
import 'entity_repository.dart';

class ApiLoanRepository extends ApiRepository<Loan, SimpleQuery>
    implements LoanRepository {
  ApiLoanRepository({required super.dio}) : super(resource: 'loans');

  @override
  Loan fromJson(Map<String, dynamic> json) => Loan.fromJson(json);

  @override
  Map<String, dynamic> toBody(Loan item) => {
        'readerId': item.readerId,
        'bookId': item.bookId,
      };

  @override
  int idOf(Loan item) => item.id;

  @override
  Map<String, dynamic> queryOf(SimpleQuery query) => {
        ...pagingQuery(
          search: '',
          sortField: query.sortField,
          sortAscending: query.sortAscending,
          page: query.page,
          size: query.size,
          includeDeleted: query.includeDeleted,
        ),
        if (query.filter.isNotEmpty) 'status': query.filter,
      };

  @override
  Future<Loan> create(Loan item) {
    throw UnsupportedError('Выдача оформляется методом issue');
  }

  @override
  Future<Loan> update(Loan item) {
    throw UnsupportedError('Выдачу можно только закрыть методом markReturned');
  }

  @override
  Future<Loan> issue({
    required int readerId,
    required int bookId,
    required int days,
  }) {
    return guard(() async {
      final response = await dio.post<dynamic>(
        '/$resource',
        data: {'readerId': readerId, 'bookId': bookId, 'days': days},
      );
      return fromJson(jsonMap(response.data));
    });
  }

  @override
  Future<Loan> markReturned(int id) {
    return guard(() async {
      final response = await dio.post<dynamic>('/$resource/$id/return');
      return fromJson(jsonMap(response.data));
    });
  }

  @override
  Future<Loan> extend(int id) {
    return guard(() async {
      try {
        final response = await dio.post<dynamic>('/$resource/$id/extend');
        return fromJson(jsonMap(response.data));
      } on DioException catch (e) {
        if (e.error is NotFoundException && '${e.error}'.contains('не обслуживается')) {
          throw const ServerException(
            'Этот сервер не умеет продлевать выдачи. Запустите tools/mock-server-pr5.js.',
          );
        }
        rethrow;
      }
    });
  }
}
