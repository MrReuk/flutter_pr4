import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_exceptions.dart';
import '../core/auth_gateway.dart';
import 'app_user.dart';
import 'auth_api.dart';
import 'permissions.dart';
import 'role.dart';
import 'session_policy.dart';

/// Почему сессия закончилась. Нужно экрану входа, чтобы объяснить причину.
enum SessionEnd {
  manual('Вы вышли из системы.'),
  inactivity('Сеанс завершён: долго не было действий.'),
  maxDuration('Сеанс завершён: исчерпана допустимая длительность сессии.'),
  tokenRejected('Сеанс завершён: сервер не принял токен. Войдите снова.');

  const SessionEnd(this.message);

  final String message;
}

const String kAccessKey = 'auth_access_token';
const String kRefreshKey = 'auth_refresh_token';
const String kStartedKey = 'auth_session_started';
const String kActivityKey = 'auth_last_activity';
const String kUserKey = 'auth_user';

/// Состояние входа: пользователь, токены и их жизненный цикл.
///
/// В localStorage (через shared_preferences) лежат токены и профиль
/// пользователя вместе с ролью: так сессия переживает перезагрузку страницы,
/// а интерфейс рисуется сразу, без запроса к серверу. Роль из localStorage
/// нужна только для интерфейса. Её можно подменить в DevTools, но права от
/// этого не появятся: сервер определяет роль по подписанному токену.
/// Настоящая роль возвращается при каждом обновлении токена.
class AuthNotifier extends ChangeNotifier implements AuthGateway {
  AuthNotifier({
    required SharedPreferences prefs,
    required AuthApi api,
    this.policy = const SessionPolicy(),
    DateTime Function()? now,
  })  : _prefs = prefs,
        _api = api,
        _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final AuthApi _api;
  final DateTime Function() _now;
  final SessionPolicy policy;

  AppUser? _user;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _startedAt;
  SessionEnd? _lastEnd;
  bool _unverified = false;
  Future<void>? _refreshing;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  AppUser? get user => _user;

  @override
  String? get accessToken => _accessToken;

  bool get isAuthenticated => _user != null;

  Role? get role => _user?.role;

  /// Токены сохранены, но проверить их не удалось: сервер недоступен.
  bool get isUnverified => _unverified;

  /// Причина последнего завершения сессии (для экрана входа).
  SessionEnd? get lastEnd => _lastEnd;

  DateTime? get sessionStartedAt => _startedAt;

  /// Когда сессия закончится в любом случае.
  DateTime? get sessionExpiresAt => _startedAt?.add(policy.maxDuration);

  /// Роль не ниже указанной.
  bool has(Role role) => _user != null && _user!.role.level >= role.level;

  /// Разрешена ли операция текущей роли (только для интерфейса).
  bool can(Permission permission) => roleCan(_user?.role, permission);

  void clearEndNotice() {
    if (_lastEnd == null) return;
    _lastEnd = null;
    notifyListeners();
  }

  /// Восстановление сессии при запуске. Вызывается один раз до runApp.
  Future<void> restore() async {
    final access = _prefs.getString(kAccessKey);
    final refresh = _prefs.getString(kRefreshKey);
    if (access == null && refresh == null) {
      _unverified = false;
      notifyListeners();
      return;
    }

    _accessToken = access;
    _refreshToken = refresh;
    _startedAt = _readTime(kStartedKey) ?? _now();

    final expired = _expiredReason();
    if (expired != null) {
      await logout(reason: expired);
      return;
    }

    try {
      if (access == null) throw const UnauthorizedException();
      final stored = _readStoredUser();
      // Профиль есть в localStorage: сервер проверит токен первым же запросом
      // (при 401 клиент обновит токены или выйдет). Профиля нет: спрашиваем /auth/me.
      _user = stored ?? await _api.me(access);
      _unverified = false;
    } on UnauthorizedException {
      try {
        if (refresh == null) throw const UnauthorizedException();
        await _applyRefresh(refresh);
        _unverified = false;
      } on NetworkException {
        _unverified = true;
      } catch (_) {
        await logout(reason: SessionEnd.tokenRejected);
        return;
      }
    } on NetworkException {
      // Сервер недоступен: сессию не сбрасываем, покажем экран с повтором.
      _unverified = true;
    } catch (_) {
      _unverified = true;
    }
    if (_user != null) {
      // Перезагрузка страницы тоже считается действием пользователя.
      await _prefs.setInt(kActivityKey, _now().millisecondsSinceEpoch);
    }
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final result = await _api.login(username, password);
    await _store(result);
    _startedAt = _now();
    _lastEnd = null;
    _unverified = false;
    await _prefs.setInt(kStartedKey, _startedAt!.millisecondsSinceEpoch);
    await _prefs.setInt(kActivityKey, _startedAt!.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// Регистрация и сразу вход под только что созданной учётной записью.
  Future<void> register({
    required String username,
    required String password,
    required String fullName,
    required String email,
  }) async {
    await _api.register(
      username: username,
      password: password,
      fullName: fullName,
      email: email,
    );
    await login(username, password);
  }

  Future<void> logout({SessionEnd reason = SessionEnd.manual}) async {
    final refresh = _refreshToken ?? _prefs.getString(kRefreshKey);
    final wasSignedIn = _user != null || _accessToken != null || refresh != null;
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _startedAt = null;
    _unverified = false;
    _lastEnd = wasSignedIn ? reason : _lastEnd;
    await _prefs.remove(kAccessKey);
    await _prefs.remove(kRefreshKey);
    await _prefs.remove(kStartedKey);
    await _prefs.remove(kActivityKey);
    await _prefs.remove(kUserKey);
    notifyListeners();
    if (wasSignedIn) await _api.logout(refresh);
  }

  @override
  Future<void> refreshTokens() {
    return _refreshing ??= _refreshOnce().whenComplete(() => _refreshing = null);
  }

  Future<void> _refreshOnce() async {
    final refresh = _refreshToken ?? _prefs.getString(kRefreshKey);
    if (refresh == null) {
      throw const UnauthorizedException('Сессия истекла. Войдите снова.');
    }
    await _applyRefresh(refresh);
  }

  Future<void> _applyRefresh(String refresh) async {
    final result = await _api.refresh(refresh);
    await _store(result);
    notifyListeners();
  }

  @override
  Future<void> sessionLost() async {
    if (_user == null && _accessToken == null) return;
    await logout(reason: SessionEnd.tokenRejected);
  }

  /// Запоминает время последнего действия: так неактивность считается
  /// и через перезагрузку страницы. Запись не чаще раза в секунду.
  void touch() {
    if (_user == null) return;
    final now = _now();
    if (now.difference(_lastWrite) < const Duration(seconds: 1)) return;
    _lastWrite = now;
    _prefs.setInt(kActivityKey, now.millisecondsSinceEpoch);
  }

  /// Выход по таймеру неактивности или по предельной длительности.
  Future<void> expire(SessionEnd reason) => logout(reason: reason);

  SessionEnd? _expiredReason() {
    final now = _now();
    final started = _startedAt;
    if (started != null && now.difference(started) >= policy.maxDuration) {
      return SessionEnd.maxDuration;
    }
    final activity = _readTime(kActivityKey);
    if (activity != null && now.difference(activity) >= policy.inactivity) {
      return SessionEnd.inactivity;
    }
    return null;
  }

  DateTime? _readTime(String key) {
    final value = _prefs.getInt(key);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> _store(AuthResult result) async {
    _accessToken = result.accessToken;
    _refreshToken = result.refreshToken;
    _user = result.user;
    await _prefs.setString(kAccessKey, result.accessToken);
    await _prefs.setString(kRefreshKey, result.refreshToken);
    await _prefs.setString(kUserKey, jsonEncode(result.user.toJson()));
  }

  AppUser? _readStoredUser() {
    final raw = _prefs.getString(kUserKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      final user = AppUser.fromJson(data);
      return user.id > 0 && user.username.isNotEmpty ? user : null;
    } catch (_) {
      return null;
    }
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
