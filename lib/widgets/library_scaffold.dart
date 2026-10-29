import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../auth/permissions.dart';
import '../state/unsaved_changes.dart';
import 'confirm_dialog.dart';

class LibraryScaffold extends StatelessWidget {
  const LibraryScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBack = false,
    this.backPath = '/',
    this.unsaved,
  });

  final String title;
  final Widget body;
  final bool showBack;
  final String backPath;
  final UnsavedChanges? unsaved;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final items = [
      for (final item in kNavItems)
        if (item.permission == null || auth.can(item.permission!)) item,
    ];
    // Подписи у кнопок меню показываем, только если они помещаются в шапку:
    // у администратора и библиотекаря разделов больше, чем у читателя.
    final narrow = MediaQuery.sizeOf(context).width < items.length * 140 + 460;

    return Scaffold(
      appBar: AppBar(
        leading: showBack
            ? BackButton(
                onPressed: () => guardedNavigate(context, unsaved, () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(backPath);
                  }
                }),
              )
            : null,
        title: Text(title),
        actions: [
          for (final item in items)
            _NavButton(
              icon: item.icon,
              label: item.label,
              onTap: () => guardedNavigate(context, unsaved, () => context.go(item.path)),
              narrow: narrow,
            ),
          const SizedBox(width: 4),
          if (auth.user != null)
            _UserMenu(auth: auth, unsaved: unsaved),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }
}

typedef NavItem = ({IconData icon, String label, String path, Permission? permission});

/// Разделы меню. Раздел виден, если роли разрешена соответствующая операция.
const List<NavItem> kNavItems = [
  (icon: Icons.home, label: 'Главная', path: '/', permission: null),
  (icon: Icons.menu_book, label: 'Книги', path: '/books', permission: Permission.viewCatalog),
  (icon: Icons.people, label: 'Авторы', path: '/authors', permission: Permission.viewCatalog),
  (icon: Icons.category, label: 'Жанры', path: '/genres', permission: Permission.viewCatalog),
  (icon: Icons.apartment, label: 'Издательства', path: '/publishers', permission: Permission.viewCatalog),
  (icon: Icons.badge, label: 'Читатели', path: '/readers', permission: Permission.viewReaders),
  (icon: Icons.assignment, label: 'Выдачи', path: '/loans', permission: Permission.viewAllLoans),
  (icon: Icons.bookmarks, label: 'Мои выдачи', path: '/my/loans', permission: Permission.viewOwnLoans),
  (icon: Icons.support_agent, label: 'Рабочее место', path: '/desk', permission: Permission.useDesk),
  (icon: Icons.manage_accounts, label: 'Пользователи', path: '/admin/users', permission: Permission.manageUsers),
  (icon: Icons.bar_chart, label: 'Статистика', path: '/admin/stats', permission: Permission.viewStats),
];

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.narrow,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    if (narrow) {
      return IconButton(tooltip: label, icon: Icon(icon), onPressed: onTap);
    }
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// Имя пользователя, его роль и выход.
class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.auth, this.unsaved});

  final AuthNotifier auth;
  final UnsavedChanges? unsaved;

  @override
  Widget build(BuildContext context) {
    final user = auth.user!;
    final showName = MediaQuery.sizeOf(context).width >= 900;
    return PopupMenuButton<String>(
      tooltip: 'Учётная запись',
      key: const ValueKey('user-menu'),
      onSelected: (value) {
        if (value != 'logout') return;
        guardedNavigate(context, unsaved, () async {
          await auth.logout();
          if (context.mounted) context.go('/login');
        });
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('${user.fullName}\n${user.role.label}'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Выйти'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: !showName
            ? const Icon(Icons.account_circle)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle),
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          user.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Text(
                        user.role.label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
      ),
    );
  }
}
