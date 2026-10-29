import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/auth/permissions.dart';
import 'package:library_app/auth/role.dart';
import 'package:library_app/auth/route_access.dart';

void main() {
  group('Права ролей (таблица раздела 2.2 контракта)', () {
    test('читатель смотрит каталог, но не изменяет его', () {
      expect(roleCan(Role.reader, Permission.viewCatalog), isTrue);
      expect(roleCan(Role.reader, Permission.manageCatalog), isFalse);
    });

    test('читатель видит только свои выдачи и не оформляет чужие', () {
      expect(roleCan(Role.reader, Permission.viewOwnLoans), isTrue);
      expect(roleCan(Role.reader, Permission.extendOwnLoan), isTrue);
      expect(roleCan(Role.reader, Permission.viewAllLoans), isFalse);
      expect(roleCan(Role.reader, Permission.manageLoans), isFalse);
    });

    test('библиотекарь ведёт каталог, читателей и выдачи', () {
      for (final permission in [
        Permission.manageCatalog,
        Permission.viewReaders,
        Permission.manageReaders,
        Permission.viewAllLoans,
        Permission.manageLoans,
        Permission.useDesk,
      ]) {
        expect(roleCan(Role.librarian, permission), isTrue, reason: '$permission');
      }
    });

    test('библиотекарь не удаляет физически, не восстанавливает и не управляет ролями', () {
      expect(roleCan(Role.librarian, Permission.hardDelete), isFalse);
      expect(roleCan(Role.librarian, Permission.restoreRecords), isFalse);
      expect(roleCan(Role.librarian, Permission.manageUsers), isFalse);
      expect(roleCan(Role.librarian, Permission.viewStats), isFalse);
    });

    test('администратору доступны удаление, восстановление, пользователи и статистика', () {
      for (final permission in [
        Permission.hardDelete,
        Permission.restoreRecords,
        Permission.manageUsers,
        Permission.viewStats,
      ]) {
        expect(roleCan(Role.admin, permission), isTrue, reason: '$permission');
      }
    });

    test('без роли (не вошёл) запрещено всё', () {
      for (final permission in Permission.values) {
        expect(roleCan(null, permission), isFalse, reason: '$permission');
      }
    });

    test('у каждой роли есть экран, недоступный остальным', () {
      List<Permission> exclusive(Role role) => [
            for (final p in Permission.values)
              if (kPermissionRoles[p]!.length == 1 && kPermissionRoles[p]!.contains(role)) p,
          ];
      expect(exclusive(Role.reader), contains(Permission.viewOwnLoans));
      expect(exclusive(Role.librarian), contains(Permission.useDesk));
      expect(exclusive(Role.admin), contains(Permission.manageUsers));
    });

    test('у каждого права есть хотя бы одна роль', () {
      for (final permission in Permission.values) {
        expect(kPermissionRoles[permission], isNotEmpty, reason: '$permission');
      }
    });

    test('неизвестная роль разбирается как отсутствие, а не как повышение', () {
      expect(Role.tryParse('superadmin'), isNull);
      expect(Role.tryParse(null), isNull);
      expect(Role.tryParse('admin'), Role.admin);
    });
  });

  group('Право, нужное для адреса', () {
    final cases = <String, Permission?>{
      '/': null,
      '/login': null,
      '/books': Permission.viewCatalog,
      '/books?search=война&page=2': Permission.viewCatalog,
      '/books/12': Permission.viewCatalog,
      '/books/new': Permission.manageCatalog,
      '/books/12/edit': Permission.manageCatalog,
      '/genres/new': Permission.manageCatalog,
      '/readers': Permission.viewReaders,
      '/readers/3/edit': Permission.manageReaders,
      '/loans': Permission.viewAllLoans,
      '/loans/new': Permission.manageLoans,
      '/my/loans': Permission.viewOwnLoans,
      '/desk': Permission.useDesk,
      '/admin/users': Permission.manageUsers,
      '/admin/stats': Permission.viewStats,
      '/admin': Permission.manageUsers,
      '/что-то-ещё': null,
    };

    cases.forEach((location, expected) {
      test(location, () => expect(requiredPermission(location), expected));
    });

    test('читателю закрыты адреса записи и разделы персонала', () {
      for (final location in ['/books/new', '/books/1/edit', '/readers', '/loans', '/admin/users']) {
        final needed = requiredPermission(location)!;
        expect(roleCan(Role.reader, needed), isFalse, reason: location);
      }
    });
  });

  group('Адрес возврата после входа', () {
    test('внутренний адрес сохраняется вместе с параметрами', () {
      expect(safeReturnTo('/books?page=2'), '/books?page=2');
    });

    test('внешние и подозрительные адреса отбрасываются', () {
      for (final value in [null, '', 'https://evil.example', '//evil.example', r'\evil', 'books']) {
        expect(safeReturnTo(value), isNull, reason: '$value');
      }
    });

    test('служебные экраны не используются как адрес возврата', () {
      for (final value in ['/login', '/login?from=%2Fbooks', '/register', '/offline', '/forbidden']) {
        expect(safeReturnTo(value), isNull, reason: value);
      }
    });
  });
}
