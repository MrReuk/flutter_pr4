import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/auth/session_policy.dart';
import 'package:library_app/auth/session_watch.dart';

void main() {
  final start = DateTime(2026, 10, 29, 9);
  const policy = SessionPolicy(
    inactivity: Duration(seconds: 180),
    warning: Duration(seconds: 30),
    maxDuration: Duration(hours: 8),
  );

  SessionWatch fresh() => SessionWatch(policy: policy, startedAt: start);
  SessionStatus at(SessionWatch watch, int seconds) =>
      watch.evaluate(start.add(Duration(seconds: seconds)));

  test('предупреждение появляется за 30 секунд до выхода', () {
    final watch = fresh();

    expect(at(watch, 0), (phase: SessionPhase.active, secondsLeft: 180));
    expect(at(watch, 149).phase, SessionPhase.active);
    expect(at(watch, 150), (phase: SessionPhase.warning, secondsLeft: 30));
    expect(at(watch, 179), (phase: SessionPhase.warning, secondsLeft: 1));
  });

  test('через три минуты без действий сессия считается неактивной', () {
    final watch = fresh();

    expect(at(watch, 180).phase, SessionPhase.inactive);
    expect(at(watch, 900).phase, SessionPhase.inactive);
  });

  test('действие пользователя сбрасывает отсчёт', () {
    final watch = fresh();

    watch.activity(start.add(const Duration(seconds: 100)));

    expect(at(watch, 249).phase, SessionPhase.active);
    expect(at(watch, 250).phase, SessionPhase.warning);
    expect(at(watch, 280).phase, SessionPhase.inactive);
  });

  test('предельная длительность сессии действует, даже если пользователь активен', () {
    final watch = fresh();
    for (var seconds = 100; seconds < const Duration(hours: 8).inSeconds; seconds += 100) {
      watch.activity(start.add(Duration(seconds: seconds)));
    }

    final almost = start.add(const Duration(hours: 8) - const Duration(seconds: 1));
    watch.activity(almost);
    expect(watch.evaluate(almost).phase, SessionPhase.active);

    final end = start.add(const Duration(hours: 8));
    watch.activity(end);
    expect(watch.evaluate(end).phase, SessionPhase.expired);
  });

  test('предупреждение не длиннее самого срока бездействия', () {
    const odd = SessionPolicy(
      inactivity: Duration(seconds: 20),
      warning: Duration(seconds: 30),
    );

    expect(odd.warnAfter, Duration.zero);
  });
}
