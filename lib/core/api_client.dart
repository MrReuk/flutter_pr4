import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exceptions.dart';
import 'auth_gateway.dart';
import 'config.dart';

const List<Duration> kRetryDelays = [
  Duration(milliseconds: 600),
  Duration(milliseconds: 1500),
];

const String _kReauthorized = 'reauthorized';

BaseOptions _baseOptions(String? baseUrl) {
  return BaseOptions(
    baseUrl: baseUrl ?? apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    validateStatus: (status) => status != null && status < 500,
  );
}

/// Основной клиент: токен в каждом запросе, обновление токена при 401,
/// повторы чтения при сбоях сети.
Dio buildDio({
  String? baseUrl,
  AuthGateway? auth,
  HttpClientAdapter? adapter,
  List<Duration> retryDelays = kRetryDelays,
  Map<String, String> debugFlags = const {},
}) {
  final dio = Dio(_baseOptions(baseUrl));
  if (adapter != null) dio.httpClientAdapter = adapter;

  dio.interceptors.add(_AuthInterceptor(auth));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra['startedAt'] = DateTime.now().millisecondsSinceEpoch;
        if (debugFlags.isNotEmpty) options.queryParameters.addAll(debugFlags);
        return handler.next(options);
      },
      onResponse: (response, handler) {
        final status = response.statusCode ?? 0;
        _log(response.requestOptions, '$status');
        if (status >= 400) {
          return handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: mapHttpError(status, response.data),
            ),
            true,
          );
        }
        return handler.next(response);
      },
      onError: (error, handler) {
        if (error.error is! ApiException) {
          final status = error.response?.statusCode;
          _log(error.requestOptions, status == null ? error.type.name : '$status');
        }
        return handler.next(error);
      },
    ),
  );

  dio.interceptors.add(_RecoveryInterceptor(dio: dio, auth: auth, delays: retryDelays));

  return dio;
}

/// Клиент для запросов /auth/*. Без перехватчиков: ошибка входа с кодом 401
/// не должна запускать обновление токена, иначе получится цикл.
Dio buildAuthDio({String? baseUrl, HttpClientAdapter? adapter}) {
  final dio = Dio(_baseOptions(baseUrl));
  if (adapter != null) dio.httpClientAdapter = adapter;
  return dio;
}

void _log(RequestOptions options, String outcome) {
  if (!kDebugMode) return;
  final started = options.extra['startedAt'];
  final elapsed = started is int
      ? ' ${DateTime.now().millisecondsSinceEpoch - started} мс'
      : '';
  debugPrint('[API] ${options.method} ${options.uri} → $outcome$elapsed');
}

bool _isAuthCall(RequestOptions options) => options.path.startsWith('/auth/');

/// Добавляет заголовок Authorization ко всем запросам, кроме /auth/*.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this.auth);

  final AuthGateway? auth;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = auth?.accessToken;
    if (token != null && !_isAuthCall(options)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

class _RecoveryInterceptor extends Interceptor {
  _RecoveryInterceptor({
    required this.dio,
    required this.auth,
    required this.delays,
  });

  final Dio dio;
  final AuthGateway? auth;
  final List<Duration> delays;

  bool _isNetworkFailure(DioException error) {
    if (error.response != null) return false;
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        true,
      _ => false,
    };
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.type == DioExceptionType.cancel) return handler.next(err);

    final options = err.requestOptions;
    final gateway = auth;

    if (err.response?.statusCode == 401 && gateway != null && !_isAuthCall(options)) {
      return _onUnauthorized(err, gateway, handler);
    }

    final attempt = (options.extra['retryAttempt'] as int?) ?? 0;
    if (options.method.toUpperCase() == 'GET' &&
        _isNetworkFailure(err) &&
        attempt < delays.length) {
      await Future<void>.delayed(delays[attempt]);
      options.extra['retryAttempt'] = attempt + 1;
      return _replay(options, handler);
    }

    return handler.next(err);
  }

  Future<void> _onUnauthorized(
    DioException err,
    AuthGateway gateway,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;

    // Уже повторяли этот запрос с новым токеном, а ответ снова 401:
    // обновлять токен ещё раз бессмысленно. Выходим, чтобы не зациклиться.
    if (options.extra[_kReauthorized] == true) {
      await gateway.sessionLost();
      return handler.next(
        _failed(options, const UnauthorizedException('Сессия истекла. Войдите снова.')),
      );
    }
    options.extra[_kReauthorized] = true;

    // Токен в запросе уже старше текущего: его успели обновить параллельным
    // запросом. Достаточно повторить с новым токеном.
    final sent = options.headers['Authorization'];
    final current = gateway.accessToken;
    final alreadyRefreshed = current != null && sent != 'Bearer $current';

    if (!alreadyRefreshed) {
      try {
        await gateway.refreshTokens();
      } on ApiException catch (e) {
        // Сервер недоступен: это не повод разрывать сессию.
        if (e is NetworkException || e is ServerException) {
          return handler.next(_failed(options, e));
        }
        await gateway.sessionLost();
        return handler.next(
          _failed(options, const UnauthorizedException('Сессия истекла. Войдите снова.')),
        );
      } catch (_) {
        await gateway.sessionLost();
        return handler.next(
          _failed(options, const UnauthorizedException('Сессия истекла. Войдите снова.')),
        );
      }
    }

    return _replay(options, handler);
  }

  DioException _failed(RequestOptions options, ApiException error) {
    return DioException(
      requestOptions: options,
      error: error,
      type: DioExceptionType.unknown,
    );
  }

  Future<void> _replay(
    RequestOptions options,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.reject(e);
    }
  }
}
