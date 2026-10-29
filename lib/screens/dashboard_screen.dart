import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../auth/permissions.dart';
import '../repositories/stats_repository.dart';
import '../state/paged_list_notifier.dart';
import '../widgets/library_scaffold.dart';

String _two(int value) => value.toString().padLeft(2, '0');

String _time(DateTime value) => '${_two(value.hour)}:${_two(value.minute)}';

/// Главный экран. Набор плиток и сводка зависят от роли.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  LoanCounts? _counts;
  String? _countsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthNotifier>();
    if (!auth.can(Permission.viewOwnLoans) && !auth.can(Permission.viewAllLoans)) return;
    final stats = context.read<StatsRepository>();
    try {
      final counts = await stats.loanCounts();
      if (mounted) setState(() => _counts = counts);
    } catch (e) {
      if (mounted) setState(() => _countsError = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final user = auth.user;
    final theme = Theme.of(context);
    final tiles = [
      for (final item in kNavItems)
        if (item.permission != null && auth.can(item.permission!)) item,
    ];
    final own = auth.can(Permission.viewOwnLoans);
    final expires = auth.sessionExpiresAt;

    return LibraryScaffold(
      title: 'Главная',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Здравствуйте, ${user?.fullName ?? ''}!',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                key: const ValueKey('role-chip'),
                                avatar: const Icon(Icons.verified_user, size: 18),
                                label: Text('Роль: ${user?.role.label ?? '—'}'),
                              ),
                              if (_counts != null)
                                Chip(
                                  label: Text(
                                    own
                                        ? 'На руках: ${_counts!.active + _counts!.overdue}'
                                        : 'Выдано сейчас: ${_counts!.active + _counts!.overdue}',
                                  ),
                                ),
                              if (_counts != null)
                                Chip(
                                  backgroundColor: _counts!.overdue > 0
                                      ? theme.colorScheme.errorContainer
                                      : null,
                                  label: Text('Просрочено: ${_counts!.overdue}'),
                                ),
                              if (expires != null)
                                Chip(label: Text('Сессия до ${_time(expires)}')),
                            ],
                          ),
                          if (_countsError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Не удалось получить сводку: $_countsError',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Разделы', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final item in tiles)
                        SizedBox(
                          width: 200,
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => context.go(item.path),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Icon(item.icon, size: 36),
                                    const SizedBox(height: 8),
                                    Text(item.label, textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Права вашей роли', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Это подсказка интерфейса. Решение о каждой операции всё равно принимает сервер.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final permission in Permission.values)
                          ListTile(
                            dense: true,
                            leading: Icon(
                              auth.can(permission) ? Icons.check_circle : Icons.lock_outline,
                              color: auth.can(permission)
                                  ? Colors.green
                                  : theme.colorScheme.outline,
                            ),
                            title: Text(permission.title),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
