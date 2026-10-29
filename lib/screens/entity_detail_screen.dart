import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../auth/permissions.dart';
import '../state/detail_notifier.dart';
import '../state/load_status.dart';
import '../widgets/detail_layout.dart';
import '../widgets/library_scaffold.dart';
import '../widgets/state_views.dart';

class EntityDetailScreen<T> extends StatelessWidget {
  const EntityDetailScreen({
    super.key,
    required this.title,
    required this.listPath,
    required this.listLabel,
    required this.notFoundMessage,
    required this.editLocation,
    required this.nameOf,
    required this.isDeleted,
    required this.fields,
    this.editPermission = Permission.manageCatalog,
  });

  final String title;
  final String listPath;
  final String listLabel;
  final String notFoundMessage;
  final String Function(T item) editLocation;
  final String Function(T item) nameOf;
  final bool Function(T item) isDeleted;
  final List<Widget> Function(BuildContext context, T item) fields;
  final Permission editPermission;

  @override
  Widget build(BuildContext context) {
    final detail = context.watch<DetailNotifier<T>>();

    return LibraryScaffold(
      title: title,
      showBack: true,
      backPath: listPath,
      body: switch (detail.status) {
        LoadStatus.idle || LoadStatus.loading => const LoadingView(),
        LoadStatus.error => ErrorView(
            message: detail.error ?? 'Неизвестная ошибка',
            onRetry: detail.load,
          ),
        LoadStatus.success => _content(context, detail),
      },
    );
  }

  Widget _content(BuildContext context, DetailNotifier<T> detail) {
    final item = detail.item;
    if (item == null) {
      return EmptyView(
        message: notFoundMessage,
        actionLabel: listLabel,
        onAction: () => context.go(listPath),
      );
    }
    return DetailLayout(
      title: nameOf(item),
      actions: [
        if (context.watch<AuthNotifier>().can(editPermission))
          FilledButton.tonalIcon(
            onPressed: () async {
              final changed = await context.push<bool>(editLocation(item));
              if (changed == true) await detail.load();
            },
            icon: const Icon(Icons.edit),
            label: const Text('Изменить'),
          ),
      ],
      children: [
        if (isDeleted(item))
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Chip(label: Text('Запись помечена как удалённая')),
          ),
        ...fields(context, item),
      ],
    );
  }
}
