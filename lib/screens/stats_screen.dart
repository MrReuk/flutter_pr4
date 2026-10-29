import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../repositories/stats_repository.dart';
import '../state/paged_list_notifier.dart';
import '../widgets/library_scaffold.dart';
import '../widgets/state_views.dart';

/// Статистика библиотеки. Раздел администратора.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  LibraryStats? _stats;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = context.read<StatsRepository>();
    try {
      final stats = await repository.load();
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось получить статистику: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LibraryScaffold(title: 'Статистика', body: _body());
  }

  Widget _body() {
    if (_loading && _stats == null) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final s = _stats!;
    final tiles = <(String, String, IconData)>[
      ('Книги', '${s.books}', Icons.menu_book),
      ('Удалённые книги', '${s.deletedBooks}', Icons.delete_outline),
      ('Авторы', '${s.authors}', Icons.people),
      ('Жанры', '${s.genres}', Icons.category),
      ('Издательства', '${s.publishers}', Icons.apartment),
      ('Читатели', '${s.readers}', Icons.badge),
      ('Выдано сейчас', '${s.activeLoans}', Icons.outbox),
      ('Просрочено', '${s.overdueLoans}', Icons.warning_amber),
      ('Возвращено', '${s.returnedLoans}', Icons.assignment_turned_in),
      ('Всего выдач', '${s.loansTotal}', Icons.assignment),
      ('Пользователи', '${s.users}', Icons.manage_accounts),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: 200,
                    child: Card(
                      key: ValueKey('stat-${tile.$1}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Icon(tile.$3, size: 28),
                            const SizedBox(height: 8),
                            Text(tile.$2, style: Theme.of(context).textTheme.headlineMedium),
                            Text(tile.$1, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
