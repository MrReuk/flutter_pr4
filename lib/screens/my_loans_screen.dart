import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_notifier.dart';
import '../models/loan.dart';
import '../models/simple_query.dart';
import '../repositories/entity_repository.dart';
import '../state/paged_list_notifier.dart';
import '../validation/validators.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/library_scaffold.dart';
import '../widgets/state_views.dart';

String _date(DateTime? value) => value == null ? '—' : formatRuDate(value);

/// Выдачи самого читателя. Отбор по читателю выполняет сервер по токену.
class MyLoansScreen extends StatefulWidget {
  const MyLoansScreen({super.key});

  @override
  State<MyLoansScreen> createState() => _MyLoansScreenState();
}

class _MyLoansScreenState extends State<MyLoansScreen> {
  List<Loan>? _loans;
  String? _error;
  bool _loading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = context.read<LoanRepository>();
    try {
      final page = await repository.find(
        SimpleQuery.initial(sortFields: kLoanSortFields, defaultSort: 'issuedAt')
            .copyWith(size: 50, sortAscending: false),
      );
      if (mounted) setState(() => _loans = page.items);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось загрузить выдачи: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _extend(Loan loan) async {
    final repository = context.read<LoanRepository>();
    setState(() => _busyId = loan.id);
    try {
      await repository.extend(loan.id);
      await _load();
    } catch (e) {
      if (mounted) {
        await showNotice(
          context,
          title: 'Продлить не удалось',
          message: describeError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthNotifier>().user;
    return LibraryScaffold(
      title: 'Мои выдачи',
      body: _body(user?.readerId),
    );
  }

  Widget _body(int? readerId) {
    if (_loading && _loans == null) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final loans = _loans ?? const <Loan>[];
    if (loans.isEmpty) {
      return EmptyView(
        message: readerId == null
            ? 'К вашей учётной записи не привязан читательский билет, поэтому выдач нет. Обратитесь к библиотекарю.'
            : 'У вас пока нет выдач.',
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: loans.length,
          itemBuilder: (context, index) {
            final loan = loans[index];
            // Продлевать можно только действующую выдачу: у просроченной книгу надо вернуть.
            final open = !loan.isClosed && !loan.isDeleted && loan.status == LoanStatus.active;
            return Card(
              child: ListTile(
                key: ValueKey('my-loan-${loan.id}'),
                leading: Icon(
                  loan.status == LoanStatus.overdue
                      ? Icons.warning_amber
                      : loan.isClosed
                          ? Icons.check_circle_outline
                          : Icons.menu_book,
                ),
                title: Text(loan.bookTitle),
                subtitle: Text(
                  'Выдана ${_date(loan.issuedAt)} · вернуть до ${_date(loan.dueAt)}\n'
                  '${loan.status.label}${loan.isClosed ? ' ${_date(loan.returnedAt)}' : ''}',
                ),
                isThreeLine: true,
                trailing: open
                    ? OutlinedButton(
                        onPressed: _busyId == null ? () => _extend(loan) : null,
                        child: _busyId == loan.id
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Продлить'),
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
