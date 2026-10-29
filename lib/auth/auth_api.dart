import 'package:dio/dio.dart';

import '../core/api_exceptions.dart';
import '../models/json_helpers.dart';
import 'app_user.dart';

class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.expiresIn = 0,
  });

  final String accessToken;
  final String refreshToken;
  final AppUser user;
  final int expiresIn;
}

/// Запросы раздела «Аутентификация» контракта. Работает на отдельном Dio
/// без перехватчиков: обновление токена не должно само вызывать обновление.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<AuthResult> login(String username, String password) {
    return guard(() async {
      final response = await _dio.post<dynamic>(
        '/auth/login',
        data: {'username': username.trim(), 'password': password},
      );
      return _result(_checked(response));
    });
  }

  Future<AuthResult> refresh(String refreshToken) {
    return guard(() async {
      final response = await _dio.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      return _result(_checked(response));
    });
  }

  Future<AppUser> register({
    required String username,
    required String password,
    required String fullName,
    required String email,
  }) {
    return guard(() async {
      final response = await _dio.post<dynamic>(
        '/auth/register',
        data: {
          'username': username.trim(),
          'password': password,
          'fullName': fullName.trim(),
          if (email.trim().isNotEmpty) 'email': email.trim(),
        },
      );
      return AppUser.fromJson(jsonMap(_checked(response)));
    });
  }

  Future<AppUser> me(String accessToken) {
    return guard(() async {
      final response = await _dio.get<dynamic>(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return AppUser.fromJson(jsonMap(_checked(response)));
    });
  }

  /// Аннулирует токен обновления на сервере. Выход не должен зависеть
  /// от успеха этого запроса, поэтому ошибки глотаются.
  Future<void> logout(String? refreshToken) async {
    if (refreshToken == null) return;
    try {
      await _dio.post<dynamic>('/auth/logout', data: {'refreshToken': refreshToken});
    } catch (_) {}
  }

  Object? _checked(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status >= 400) throw mapHttpError(status, response.data);
    return response.data;
  }

  AuthResult _result(Object? data) {
    final map = jsonMap(data);
    final access = map['accessToken'];
    final refresh = map['refreshToken'];
    if (access is! String || refresh is! String) {
      throw const ServerException('Сервер не выдал токены.');
    }
    return AuthResult(
      accessToken: access,
      refreshToken: refresh,
      expiresIn: jsonInt(map['expiresIn']),
      user: AppUser.fromJson(jsonMap(map['user'])),
    );
  }
}
