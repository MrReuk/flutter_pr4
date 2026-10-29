import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../widgets/auth_frame.dart';

/// Токены сохранены, но сервер недоступен и проверить сессию нельзя.
class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthNotifier>().restore();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      title: 'Сервер недоступен',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Не удалось проверить вашу сессию: сервер не отвечает. '
            'Вы не вышли из системы, сессия сохранена.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await context.read<AuthNotifier>().logout();
                    if (context.mounted) context.go('/login');
                  },
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}
