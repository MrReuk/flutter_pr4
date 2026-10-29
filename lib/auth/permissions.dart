import 'role.dart';

/// Операции, доступ к которым зависит от роли.
///
/// Таблица прав совпадает с разделом 2.2 контракта API. Эта проверка нужна
/// только интерфейсу: она прячет кнопки и маршруты. Настоящее решение
/// принимает сервер.
enum Permission {
  viewCatalog('Просмотр каталога, авторов, жанров и издательств'),
  manageCatalog('Создание, изменение и удаление книг и справочников'),
  viewReaders('Просмотр списка читателей'),
  manageReaders('Работа с читателями'),
  viewAllLoans('Просмотр всех выдач'),
  manageLoans('Оформление и закрытие выдач'),
  viewOwnLoans('Просмотр собственных выдач'),
  extendOwnLoan('Продление срока собственной выдачи'),
  useDesk('Рабочее место библиотекаря'),
  restoreRecords('Восстановление удалённых записей'),
  hardDelete('Физическое удаление записей'),
  manageUsers('Управление пользователями и ролями'),
  viewStats('Просмотр статистики');

  const Permission(this.title);

  final String title;
}

const Set<Role> _everyone = {Role.reader, Role.librarian, Role.admin};
const Set<Role> _staff = {Role.librarian, Role.admin};

const Map<Permission, Set<Role>> kPermissionRoles = {
  Permission.viewCatalog: _everyone,
  Permission.manageCatalog: _staff,
  Permission.viewReaders: _staff,
  Permission.manageReaders: _staff,
  Permission.viewAllLoans: _staff,
  Permission.manageLoans: _staff,
  Permission.viewOwnLoans: {Role.reader},
  Permission.extendOwnLoan: {Role.reader},
  Permission.useDesk: {Role.librarian},
  Permission.restoreRecords: {Role.admin},
  Permission.hardDelete: {Role.admin},
  Permission.manageUsers: {Role.admin},
  Permission.viewStats: {Role.admin},
};

/// Разрешена ли операция роли. Без роли (не вошёл) не разрешено ничего.
bool roleCan(Role? role, Permission permission) {
  if (role == null) return false;
  return kPermissionRoles[permission]?.contains(role) ?? false;
}
