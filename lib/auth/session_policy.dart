import '../core/config.dart';

/// Ограничения жизни сессии на клиенте.
class SessionPolicy {
  const SessionPolicy({
    this.inactivity = const Duration(seconds: inactivitySeconds),
    this.warning = const Duration(seconds: inactivityWarningSeconds),
    this.maxDuration = const Duration(minutes: maxSessionMinutes),
  });

  /// Сколько можно ничего не делать.
  final Duration inactivity;

  /// За сколько до выхода предупредить.
  final Duration warning;

  /// Предел общей длительности сессии.
  final Duration maxDuration;

  /// Через сколько бездействия показывать предупреждение.
  Duration get warnAfter {
    final value = inactivity - warning;
    return value.isNegative ? Duration.zero : value;
  }
}
