import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../auth/session_watch.dart';

/// Следит за жизнью сессии: выход после бездействия (с предупреждением
/// за 30 секунд) и по предельной длительности сессии.
///
/// Стоит над маршрутизатором, поэтому предупреждение нарисовано обычным
/// слоем поверх экрана, а не через showDialog (у него здесь нет Navigator).
class SessionGuard extends StatefulWidget {
  const SessionGuard({
    super.key,
    required this.child,
    this.now,
    this.tick = const Duration(seconds: 1),
  });

  final Widget child;

  /// Часы. В тестах подменяются, чтобы не ждать минуты.
  final DateTime Function()? now;
  final Duration tick;

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  late final AuthNotifier _auth;
  Timer? _ticker;
  SessionWatch? _watch;
  SessionStatus _status = (phase: SessionPhase.active, secondsLeft: 0);

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthNotifier>();
    _auth.addListener(_sync);
    HardwareKeyboard.instance.addHandler(_onKey);
    _sync();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _auth.removeListener(_sync);
    _ticker?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _activity();
    return false;
  }

  void _sync() {
    final signedIn = _auth.isAuthenticated && !_auth.isUnverified;
    if (signedIn && _watch == null) {
      _watch = SessionWatch(
        policy: _auth.policy,
        startedAt: _auth.sessionStartedAt ?? _now(),
        lastActivity: _now(),
      );
      _ticker?.cancel();
      _ticker = Timer.periodic(widget.tick, (_) => _onTick());
    } else if (!signedIn && _watch != null) {
      _watch = null;
      _ticker?.cancel();
      _ticker = null;
      if (_status.phase != SessionPhase.active && mounted) {
        setState(() => _status = (phase: SessionPhase.active, secondsLeft: 0));
      }
    }
  }

  void _onTick() {
    final watch = _watch;
    if (watch == null) return;
    final status = watch.evaluate(_now());
    switch (status.phase) {
      case SessionPhase.inactive:
        _stop();
        _auth.expire(SessionEnd.inactivity);
      case SessionPhase.expired:
        _stop();
        _auth.expire(SessionEnd.maxDuration);
      case SessionPhase.warning:
        if (status != _status && mounted) setState(() => _status = status);
      case SessionPhase.active:
        // Пока всё спокойно, перерисовывать нечего.
        if (_status.phase != SessionPhase.active && mounted) {
          setState(() => _status = (phase: SessionPhase.active, secondsLeft: 0));
        }
    }
  }

  void _stop() {
    _watch = null;
    _ticker?.cancel();
    _ticker = null;
    if (mounted) setState(() => _status = (phase: SessionPhase.active, secondsLeft: 0));
  }

  /// Действие пользователя. Пока показано предупреждение, обычные движения
  /// мыши не считаются: продлить сессию можно только кнопкой.
  void _activity() {
    final watch = _watch;
    if (watch == null || _status.phase == SessionPhase.warning) return;
    watch.activity(_now());
    _auth.touch();
  }

  void _stay() {
    final watch = _watch;
    if (watch == null) return;
    watch.activity(_now());
    _auth.touch();
    setState(() => _status = (phase: SessionPhase.active, secondsLeft: 0));
  }

  Future<void> _leave() async {
    _stop();
    await _auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final warning = _status.phase == SessionPhase.warning;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activity(),
      onPointerMove: (_) => _activity(),
      onPointerHover: (_) => _activity(),
      onPointerSignal: (_) => _activity(),
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (warning) ...[
            const Positioned.fill(
              child: ModalBarrier(dismissible: false, color: Colors.black54),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  key: const ValueKey('session-warning'),
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Сеанс скоро завершится',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Вы давно ничего не делали. Через ${_status.secondsLeft} с '
                          'вы будете выведены из системы.',
                          key: const ValueKey('session-warning-text'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const ValueKey('session-stay'),
                          onPressed: _stay,
                          child: const Text('Остаться в системе'),
                        ),
                        TextButton(
                          key: const ValueKey('session-leave'),
                          onPressed: _leave,
                          child: const Text('Выйти'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
