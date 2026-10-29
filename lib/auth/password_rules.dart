/// Одно правило сложности пароля и его результат для текущего значения.
typedef PasswordRuleResult = ({String label, bool ok});

const int kMinPasswordLength = 8;

final RegExp _digit = RegExp(r'\d');
final RegExp _special = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);

/// Проверяет пароль по трём правилам: длина, цифра, специальный символ.
List<PasswordRuleResult> checkPassword(String value) {
  return [
    (label: 'Не менее $kMinPasswordLength символов', ok: value.length >= kMinPasswordLength),
    (label: 'Есть цифра', ok: _digit.hasMatch(value)),
    (label: 'Есть специальный символ (например, ! ? # \$ %)', ok: _special.hasMatch(value)),
  ];
}

bool isPasswordStrong(String value) => checkPassword(value).every((r) => r.ok);

/// Сообщение для поля пароля: первое невыполненное правило или null.
String? passwordError(String value) {
  if (value.isEmpty) return 'Введите пароль';
  if (value.length < kMinPasswordLength) {
    return 'Пароль не короче $kMinPasswordLength символов';
  }
  if (!_digit.hasMatch(value)) return 'Добавьте в пароль хотя бы одну цифру';
  if (!_special.hasMatch(value)) {
    return 'Добавьте в пароль специальный символ, например ! ? # \$ %';
  }
  return null;
}
