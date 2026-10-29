import 'package:flutter/material.dart';

import '../auth/rights.dart';
import 'confirm_dialog.dart';

List<Widget> buildRowActions(
  BuildContext context, {
  required bool deleted,
  required ListRights rights,
  required String name,
  VoidCallback? onEdit,
  List<Widget> extra = const [],
  required Future<String?> Function() onSoftDelete,
  required Future<String?> Function() onHardDelete,
  required Future<String?> Function() onRestore,
}) {
  Future<void> report(Future<String?> Function() action) async {
    final problem = await action();
    if (problem == null || !context.mounted) return;
    await showNotice(context, title: 'Действие невозможно', message: problem);
  }

  return [
    ...extra,
    if (onEdit != null && rights.canManage)
      IconButton(
        tooltip: 'Изменить',
        icon: const Icon(Icons.edit_outlined),
        onPressed: onEdit,
      ),
    if (deleted && rights.canRestore)
      IconButton(
        tooltip: 'Восстановить',
        icon: const Icon(Icons.restore),
        onPressed: () => report(onRestore),
      )
    else if (!deleted && rights.canManage)
      IconButton(
        tooltip: 'Удалить',
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final confirmed = await confirmAction(
            context,
            title: 'Удалить запись?',
            message: '«$name» будет помечена как удалённая. Её можно восстановить.',
          );
          if (confirmed) await report(onSoftDelete);
        },
      ),
    if (rights.canHardDelete)
      IconButton(
        tooltip: 'Удалить навсегда',
        icon: Icon(
          Icons.delete_forever,
          color: Theme.of(context).colorScheme.error,
        ),
        onPressed: () async {
          final confirmed = await confirmAction(
            context,
            title: 'Удалить навсегда?',
            message: '«$name» будет стёрта без возможности восстановления.',
            confirmLabel: 'Удалить навсегда',
          );
          if (confirmed) await report(onHardDelete);
        },
      ),
  ];
}
