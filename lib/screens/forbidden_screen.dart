import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../widgets/library_scaffold.dart';

/// Экран отказа: пользователь вошёл, но этот адрес его роли недоступен.
class ForbiddenScreen extends StatelessWidget {
  const ForbiddenScreen({super.key, this.attempted});

  /// Адрес, который пытались открыть.
  final String? attempted;

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthNotifier>().user?.role.label ?? '—';
    final scheme = Theme.of(context).colorScheme;
    return LibraryScaffold(
      title: 'Доступ запрещён',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                'У роли «$role» нет доступа к этому разделу',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (attempted != null && attempted!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Адрес: $attempted',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('На главную'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
