import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/app_user.dart';
import '../auth/auth_notifier.dart';
import '../auth/role.dart';
import '../models/page_result.dart';
import '../repositories/user_repository.dart';
import '../state/paged_list_notifier.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/library_scaffold.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/state_views.dart';

/// Пользователи и роли. Раздел администратора.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  PageResult<AppUser> _result = PageResult<AppUser>.empty();
  int _page = 1;
  int _size = 10;
  bool _loading = true;
  String? _error;
  int? _busyId;

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
    final repository = context.read<UserRepository>();
    try {
      final loaded = await repository.find(page: _page, size: _size);
      if (mounted) setState(() => _result = loaded);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось загрузить пользователей: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeRole(AppUser user, Role role) async {
    if (role == user.role) return;
    final self = context.read<AuthNotifier>().user;
    if (self != null && self.id == user.id) {
      await showNotice(
        context,
        title: 'Нельзя менять свою роль',
        message: 'Администратор не может изменить собственную роль: так можно случайно остаться без доступа.',
      );
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Изменить роль?',
      message: 'Пользователь «${user.fullName}»: ${user.role.label} → ${role.label}.',
      confirmLabel: 'Изменить',
    );
    if (!ok || !mounted) return;
    final repository = context.read<UserRepository>();
    setState(() => _busyId = user.id);
    try {
      await repository.changeRole(user.id, role);
      await _load();
    } catch (e) {
      if (mounted) {
        await showNotice(context, title: 'Роль не изменена', message: describeError(e));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LibraryScaffold(
      title: 'Пользователи и роли',
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _result.items.isEmpty) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_result.items.isEmpty) return const EmptyView(message: 'Пользователей нет.');
    final self = context.watch<AuthNotifier>().user;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _result.items.length,
                itemBuilder: (context, index) {
                  final user = _result.items[index];
                  final isSelf = self?.id == user.id;
                  return Card(
                    child: ListTile(
                      key: ValueKey('user-${user.id}'),
                      leading: const Icon(Icons.account_circle),
                      title: Text(isSelf ? '${user.fullName} (вы)' : user.fullName),
                      subtitle: Text(
                        '${user.username}${user.email.isEmpty ? '' : ' · ${user.email}'}',
                      ),
                      trailing: SizedBox(
                        width: 190,
                        child: DropdownButton<Role>(
                          key: ValueKey('role-${user.id}'),
                          value: user.role,
                          isExpanded: true,
                          onChanged: _busyId == null && !isSelf
                              ? (role) {
                                  if (role != null) _changeRole(user, role);
                                }
                              : null,
                          items: [
                            for (final role in Role.values)
                              DropdownMenuItem<Role>(value: role, child: Text(role.label)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            PaginationBar(
              result: _result,
              onPage: (page) {
                _page = page;
                _load();
              },
              onSize: (size) {
                _size = size;
                _page = 1;
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }
}
