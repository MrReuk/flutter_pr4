import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../auth/password_rules.dart';
import '../core/api_exceptions.dart';
import '../repositories/repository_exception.dart';
import '../validation/validators.dart';
import '../widgets/auth_frame.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;
  Map<String, String> _serverErrors = const {};

  @override
  void initState() {
    super.initState();
    // Список правил обновляется по мере ввода, а не по нажатию кнопки.
    _password.addListener(() => setState(() {}));
    _repeat.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  String? _fromServer(String key) => _serverErrors[key];

  void _clearServerErrors() {
    if (_serverErrors.isNotEmpty) setState(() => _serverErrors = const {});
  }

  Future<void> _submit() async {
    setState(() => _serverErrors = const {});
    if (_busy || !_formKey.currentState!.validate()) return;
    final auth = context.read<AuthNotifier>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.register(
        username: _username.text,
        password: _password.text,
        fullName: _fullName.text,
        email: _email.text,
      );
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _serverErrors = e.errors;
          _formKey.currentState?.validate();
        });
      }
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = checkPassword(_password.text);
    final scheme = Theme.of(context).colorScheme;

    return AuthFrame(
      title: 'Регистрация',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) NoticeBanner(message: _error!),
            TextFormField(
              key: const ValueKey('register-fullName'),
              onChanged: (_) => _clearServerErrors(),
              controller: _fullName,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'ФИО',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final text = value ?? '';
                return checks([
                  notBlank('Введите ФИО'),
                  minLength(3),
                  maxLength(80),
                ])(text, const {}) ??
                    _fromServer('fullName');
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('register-username'),
              onChanged: (_) => _clearServerErrors(),
              controller: _username,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Логин',
                helperText: 'Не короче трёх символов, без пробелов',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'Введите логин';
                if (text.length < 3) return 'Логин не короче трёх символов';
                if (text.contains(RegExp(r'\s'))) return 'В логине не должно быть пробелов';
                return _fromServer('username');
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('register-email'),
              onChanged: (_) => _clearServerErrors(),
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Электронная почта (необязательно)',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  emailFormat()((value ?? '').trim()) ?? _fromServer('email'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('register-password'),
              onChanged: (_) => _clearServerErrors(),
              controller: _password,
              enabled: !_busy,
              obscureText: _hidden,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Пароль',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'Показать пароль' : 'Скрыть пароль',
                  icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
              validator: (value) => passwordError(value ?? '') ?? _fromServer('password'),
            ),
            const SizedBox(height: 8),
            for (final rule in rules)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      rule.ok ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 18,
                      color: rule.ok ? Colors.green : scheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.label,
                        style: TextStyle(
                          color: rule.ok ? Colors.green : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('register-repeat'),
              controller: _repeat,
              enabled: !_busy,
              obscureText: _hidden,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Повторите пароль',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) return 'Повторите пароль';
                return value == _password.text ? null : 'Пароли не совпадают';
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('register-submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Зарегистрироваться'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => context.go('/login'),
              child: const Text('Уже есть учётная запись? Войти'),
            ),
          ],
        ),
      ),
    );
  }
}
