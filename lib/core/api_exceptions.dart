import 'package:dio/dio.dart';

import '../repositories/repository_exception.dart';

sealed class ApiException extends RepositoryException {
  const ApiException(super.message);
}

class NetworkException extends ApiException {
  const NetworkException([super.message = 'Сервер недоступен. Проверьте соединение.']);
}

class CancelledException extends ApiException {
  const CancelledException([super.message = 'Запрос отменён.']);
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException([super.message = 'Требуется вход в систему.']);
}

class ForbiddenException extends ApiException {
  const ForbiddenException([super.message = 'Недостаточно прав для этого действия.']);
}

class NotFoundException extends ApiException {
  const NotFoundException([super.message = 'Запись не найдена.']);
}

class ConflictException extends ApiException {
  const ConflictException(super.message);
}

class ValidationException extends ApiException {
  final Map<String, String> errors;

  const ValidationException(super.message, this.errors);
}

class ServerException extends ApiException {
  const ServerException([super.message = 'Ошибка на сервере. Попробуйте позже.']);
}

ApiException mapHttpError(int status, dynamic body) {
  final message = (body is Map && body['message'] is String)
      ? body['message'] as String
      : null;

  return switch (status) {
    401 => UnauthorizedException(message ?? 'Требуется вход в систему.'),
    403 => ForbiddenException(
        message == null
            ? 'Недостаточно прав для этого действия.'
            : 'Недостаточно прав для этого действия. ${message.endsWith('.') ? message : '$message.'}',
      ),
    404 => NotFoundException(message ?? 'Запись не найдена.'),
    409 => ConflictException(message ?? 'Операция невозможна.'),
    422 => ValidationException(
        message ?? 'Ошибка валидации',
        (body is Map && body['errors'] is Map)
            ? (body['errors'] as Map).map((k, v) => MapEntry('$k', '$v'))
            : const {},
      ),
    _ => ServerException(
        message ??
            (status >= 500
                ? 'Ошибка на сервере. Попробуйте позже.'
                : 'Неизвестная ошибка (код $status).'),
      ),
  };
}

ApiException mapDioError(DioException e) {
  final existing = e.error;
  if (existing is ApiException) return existing;

  final response = e.response;
  if (response != null) {
    return mapHttpError(response.statusCode ?? 0, response.data);
  }

  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      const NetworkException('Сервер не ответил вовремя.'),
    DioExceptionType.connectionError => const NetworkException(
        'Не удалось соединиться с сервером. '
        'Если сервер запущен, откройте консоль браузера и проверьте наличие ошибки CORS.',
      ),
    DioExceptionType.badCertificate =>
      const NetworkException('Не удалось установить защищённое соединение.'),
    DioExceptionType.cancel => const CancelledException(),
    _ => const ServerException(),
  };
}

ValidationException _renamed(ValidationException e, Map<String, String> keys) {
  if (keys.isEmpty) return e;
  return ValidationException(e.message, {
    for (final entry in e.errors.entries) (keys[entry.key] ?? entry.key): entry.value,
  });
}

Future<T> guard<T>(
  Future<T> Function() action, {
  Map<String, String> fieldKeys = const {},
}) async {
  try {
    return await action();
  } on DioException catch (e) {
    final mapped = mapDioError(e);
    throw mapped is ValidationException ? _renamed(mapped, fieldKeys) : mapped;
  } on ValidationException catch (e) {
    throw _renamed(e, fieldKeys);
  } on TypeError {
    throw const ServerException('Сервер вернул ответ в неожиданном формате.');
  } on FormatException {
    throw const ServerException('Сервер вернул ответ в неожиданном формате.');
  }
}
