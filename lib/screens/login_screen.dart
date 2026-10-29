import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../repositories/repository_exception.dart';
import '../widgets/auth_frame.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final auth = context.read<AuthNotifier>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.login(_username.text, _password.text);
      // Переход выполнит сам маршрутизатор: он слушает AuthNotifier
      // и вернёт пользователя туда, куда он шёл (параметр from).
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final ended = auth.lastEnd;

    return AuthFrame(
      title: 'Вход в систему',
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ended != null)
              NoticeBanner(
                message: ended.message,
                isError: ended != SessionEnd.manual,
                onClose: auth.clearEndNotice,
              ),
            if (_error != null) NoticeBanner(message: _error!),
            TextFormField(
              key: const ValueKey('login-username'),
              controller: _username,
              enabled: !_busy,
              autofocus: true,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Логин',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Введите логин' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('login-password'),
              controller: _password,
              enabled: !_busy,
              obscureText: _hidden,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Пароль',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'Показать пароль' : 'Скрыть пароль',
                  icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
              validator: (value) => (value ?? '').isEmpty ? 'Введите пароль' : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('login-submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Войти'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => context.go('/register'),
              child: const Text('Нет учётной записи? Зарегистрироваться'),
            ),
          ],
        ),
      ),
    );
  }
}
