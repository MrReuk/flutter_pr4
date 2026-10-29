import '../auth/app_user.dart';
import '../auth/role.dart';
import '../models/page_result.dart';

/// Управление пользователями (только администратор).
abstract interface class UserRepository {
  Future<PageResult<AppUser>> find({int page = 1, int size = kDefaultPageSize});

  /// Меняет роль. Нужен сервер с адресом PATCH /users/{id}.
  Future<AppUser> changeRole(int id, Role role);
}
