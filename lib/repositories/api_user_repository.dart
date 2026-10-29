import 'package:dio/dio.dart';

import '../auth/app_user.dart';
import '../auth/role.dart';
import '../core/api_exceptions.dart';
import '../models/json_helpers.dart';
import '../models/page_result.dart';
import 'user_repository.dart';

class ApiUserRepository implements UserRepository {
  ApiUserRepository({required this.dio});

  final Dio dio;

  @override
  Future<PageResult<AppUser>> find({int page = 1, int size = kDefaultPageSize}) {
    return guard(() async {
      final response = await dio.get<dynamic>(
        '/users',
        queryParameters: {'page': page, 'size': size, 'sort': 'id,asc'},
      );
      final map = jsonMap(response.data);
      final raw = map['items'];
      if (raw is! List) throw const FormatException('В ответе нет списка items');
      return PageResult<AppUser>(
        items: [for (final e in raw) AppUser.fromJson(jsonMap(e))],
        page: jsonInt(map['page'], 1),
        size: jsonInt(map['size'], size),
        total: jsonInt(map['total']),
      );
    });
  }

  @override
  Future<AppUser> changeRole(int id, Role role) {
    return guard(() async {
      try {
        final response = await dio.patch<dynamic>(
          '/users/$id',
          data: {'role': role.code},
        );
        return AppUser.fromJson(jsonMap(response.data));
      } on DioException catch (e) {
        if (e.error is NotFoundException && '${e.error}'.contains('Ресурс не найден')) {
          throw const ServerException(
            'Этот сервер не умеет менять роли. Запустите tools/mock-server-pr5.js.',
          );
        }
        rethrow;
      }
    });
  }
}
