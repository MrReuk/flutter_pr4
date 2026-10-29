import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'auth_notifier.dart';
import 'permissions.dart';

/// Что из управляющих элементов списка показывать текущему пользователю.
/// Это только уборка интерфейса: решение принимает сервер.
class ListRights {
  const ListRights({
    required this.canManage,
    required this.canRestore,
    required this.canHardDelete,
  });

  final bool canManage;
  final bool canRestore;
  final bool canHardDelete;
}

ListRights listRights(BuildContext context, Permission manage) {
  final auth = context.watch<AuthNotifier>();
  return ListRights(
    canManage: auth.can(manage),
    canRestore: auth.can(Permission.restoreRecords),
    canHardDelete: auth.can(Permission.hardDelete),
  );
}
