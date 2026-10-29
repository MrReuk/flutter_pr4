import 'permissions.dart';

/// Какое право нужно для открытия адреса. null: достаточно войти.
///
/// Это правило пользуется и маршрутизатор (redirect), и тесты. Оно только
/// решает, что показать: чужие данные всё равно не отдаст сервер.
Permission? requiredPermission(String location) {
  final path = Uri.parse(location).path;
  final segments = [
    for (final s in path.split('/'))
      if (s.isNotEmpty) s,
  ];
  if (segments.isEmpty) return null;

  final writes =
      segments.length >= 2 && (segments[1] == 'new' || segments.last == 'edit');

  switch (segments.first) {
    case 'books':
    case 'authors':
    case 'genres':
    case 'publishers':
      return writes ? Permission.manageCatalog : Permission.viewCatalog;
    case 'readers':
      return writes ? Permission.manageReaders : Permission.viewReaders;
    case 'loans':
      return writes ? Permission.manageLoans : Permission.viewAllLoans;
    case 'my':
      return Permission.viewOwnLoans;
    case 'desk':
      return Permission.useDesk;
    case 'admin':
      final section = segments.length >= 2 ? segments[1] : '';
      return section == 'stats' ? Permission.viewStats : Permission.manageUsers;
  }
  return null;
}

const Set<String> _publicPaths = {'/login', '/register'};

bool isPublicPath(String path) => _publicPaths.contains(path);

/// Куда можно вернуться после входа. Принимаются только внутренние адреса
/// приложения: иначе параметр from превратился бы в открытое перенаправление.
String? safeReturnTo(String? from) {
  if (from == null || from.isEmpty) return null;
  if (!from.startsWith('/') || from.startsWith('//') || from.contains('\\')) {
    return null;
  }
  final path = Uri.tryParse(from)?.path;
  if (path == null) return null;
  if (isPublicPath(path) || path == '/offline' || path == '/forbidden') return null;
  return from;
}
