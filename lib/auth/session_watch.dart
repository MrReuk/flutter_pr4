import 'session_policy.dart';

/// Состояние сессии с точки зрения таймеров.
enum SessionPhase {
  /// Всё в порядке.
  active,

  /// Бездействие подходит к пределу: пора предупредить.
  warning,

  /// Бездействие превысило предел.
  inactive,

  /// Исчерпана общая длительность сессии.
  expired,
}

typedef SessionStatus = ({SessionPhase phase, int secondsLeft});

/// Считает, в какой фазе находится сессия. Не знает про таймеры и виджеты:
/// время передаётся снаружи, поэтому логику легко проверить тестом.
class SessionWatch {
  SessionWatch({
    required this.policy,
    required DateTime startedAt,
    DateTime? lastActivity,
  })  : _startedAt = startedAt,
        _lastActivity = lastActivity ?? startedAt;

  final SessionPolicy policy;
  final DateTime _startedAt;
  DateTime _lastActivity;

  DateTime get lastActivity => _lastActivity;

  /// Пользователь что-то сделал.
  void activity(DateTime now) {
    _lastActivity = now;
  }

  /// Сколько секунд осталось до выхода по неактивности (округление вверх).
  int secondsLeft(DateTime now) {
    final left = policy.inactivity - now.difference(_lastActivity);
    if (left <= Duration.zero) return 0;
    return (left.inMilliseconds / 1000).ceil();
  }

  SessionStatus evaluate(DateTime now) {
    if (now.difference(_startedAt) >= policy.maxDuration) {
      return (phase: SessionPhase.expired, secondsLeft: 0);
    }
    final idle = now.difference(_lastActivity);
    if (idle >= policy.inactivity) {
      return (phase: SessionPhase.inactive, secondsLeft: 0);
    }
    if (idle >= policy.warnAfter) {
      return (phase: SessionPhase.warning, secondsLeft: secondsLeft(now));
    }
    return (phase: SessionPhase.active, secondsLeft: secondsLeft(now));
  }
}
