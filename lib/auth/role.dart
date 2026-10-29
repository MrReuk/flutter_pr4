/// Роли пользователей. Уровень нужен только для сравнения «не ниже».
enum Role {
  reader(1, 'reader', 'Читатель'),
  librarian(2, 'librarian', 'Библиотекарь'),
  admin(3, 'admin', 'Администратор');

  const Role(this.level, this.code, this.label);

  final int level;
  final String code;
  final String label;

  /// Возвращает null для неизвестного значения: решать, что с ним делать,
  /// должен вызывающий код (по умолчанию – наименьшие права).
  static Role? tryParse(Object? value) {
    for (final role in Role.values) {
      if (role.code == value) return role;
    }
    return null;
  }
}
