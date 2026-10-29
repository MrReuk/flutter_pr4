import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/auth/password_rules.dart';

List<bool> _marks(String value) => [for (final r in checkPassword(value)) r.ok];

void main() {
  test('пустой пароль не выполняет ни одного правила', () {
    expect(_marks(''), [false, false, false]);
    expect(passwordError(''), 'Введите пароль');
  });

  test('правила проверяются независимо: длина, цифра, спецсимвол', () {
    expect(_marks('abcdefgh'), [true, false, false]);
    expect(_marks('abcdefg1'), [true, true, false]);
    expect(_marks('a1!'), [false, true, true]);
    expect(_marks('abcdef1!'), [true, true, true]);
  });

  test('пароль принимается только при выполнении всех трёх правил', () {
    expect(isPasswordStrong('abcdef1!'), isTrue);
    expect(isPasswordStrong('abcdefg1'), isFalse);
    expect(isPasswordStrong('abcdefg!'), isFalse);
    expect(isPasswordStrong('a1!'), isFalse);
  });

  test('сообщение называет первое невыполненное правило', () {
    expect(passwordError('a1!'), contains('не короче 8'));
    expect(passwordError('abcdefgh!'), contains('цифру'));
    expect(passwordError('abcdefg1'), contains('специальный символ'));
    expect(passwordError('abcdef1!'), isNull);
  });

  test('русские буквы и пробел не считаются специальными символами', () {
    expect(_marks('пароль123'), [true, true, false]);
    expect(_marks('abc defg1'), [true, true, false]);
    expect(isPasswordStrong('пароль123_'), isTrue);
  });
}
