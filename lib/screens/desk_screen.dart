import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/loan.dart';
import '../models/named_option.dart';
import '../models/simple_query.dart';
import '../repositories/entity_repository.dart';
import '../state/paged_list_notifier.dart';
import '../state/reference_notifier.dart';
import '../validation/validators.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/library_scaffold.dart';
import '../widgets/state_views.dart';

String _date(DateTime? value) => value == null ? '—' : formatRuDate(value);

/// Рабочее место библиотекаря: быстрая выдача и приём книг.
/// Раздел виден только библиотекарю, остальным роутер показывает отказ.
class DeskScreen extends StatefulWidget {
  const DeskScreen({super.key});

  @override
  State<DeskScreen> createState() => _DeskScreenState();
}

class _DeskScreenState extends State<DeskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _days = TextEditingController(text: '14');
  int? _readerId;
  int? _bookId;
  bool _issuing = false;
  String? _message;
  String? _problem;

  List<Loan>? _loans;
  String? _loadError;
  bool _loading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReferenceNotifier>().load(withLinks: true);
      _load();
    });
  }

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final repository = context.read<LoanRepository>();
    try {
      final base = SimpleQuery.initial(sortFields: kLoanSortFields, defaultSort: 'dueAt')
          .copyWith(size: 50);
      final overdue = await repository.find(base.copyWith(filter: 'overdue'));
      final active = await repository.find(base.copyWith(filter: 'active'));
      if (mounted) setState(() => _loans = [...overdue.items, ...active.items]);
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Не удалось загрузить выдачи: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _issue() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<LoanRepository>();
    final refs = context.read<ReferenceNotifier>();
    setState(() {
      _issuing = true;
      _message = null;
      _problem = null;
    });
    try {
      await repository.issue(
        readerId: _readerId!,
        bookId: _bookId!,
        days: int.parse(_days.text.trim()),
      );
      await refs.load(withLinks: true);
      await _load();
      if (mounted) {
        setState(() {
          _message = 'Выдача оформлена.';
          _bookId = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _problem = describeError(e));
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _return(Loan loan) async {
    final repository = context.read<LoanRepository>();
    setState(() => _busyId = loan.id);
    try {
      await repository.markReturned(loan.id);
      await _load();
    } catch (e) {
      if (mounted) {
        await showNotice(context, title: 'Принять книгу не удалось', message: describeError(e));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Widget _dropdown({
    required Key key,
    required String label,
    required int? value,
    required List<NamedOption> options,
    required ValueChanged<int?> onChanged,
    required String emptyError,
  }) {
    final current = options.any((o) => o.id == value) ? value : null;
    return DropdownButtonFormField<int>(
      key: key,
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final option in options)
          DropdownMenuItem<int>(value: option.id, child: Text(option.name)),
      ],
      validator: (value) => value == null ? emptyError : null,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final refs = context.watch<ReferenceNotifier>();
    final theme = Theme.of(context);
    return LibraryScaffold(
      title: 'Рабочее место библиотекаря',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Выдать книгу', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 12),
                            if (!refs.ready && !refs.failed)
                              const LinearProgressIndicator()
                            else if (refs.failed)
                              Text(
                                'Не удалось загрузить справочники: ${refs.error}',
                                style: TextStyle(color: theme.colorScheme.error),
                              )
                            else ...[
                              _dropdown(
                                key: ValueKey('reader-${refs.readerOptions().length}'),
                                label: 'Читатель',
                                value: _readerId,
                                options: refs.readerOptions(),
                                onChanged: (v) => setState(() => _readerId = v),
                                emptyError: 'Выберите читателя',
                              ),
                              const SizedBox(height: 12),
                              _dropdown(
                                key: ValueKey('book-${refs.bookOptions().length}-$_bookId'),
                                label: 'Книга',
                                value: _bookId,
                                options: refs.bookOptions(),
                                onChanged: (v) => setState(() => _bookId = v),
                                emptyError: 'Выберите книгу',
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const ValueKey('desk-days'),
                                controller: _days,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: 'Срок выдачи, дней',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final text = value ?? '';
                                  return notBlank()(text) ?? integerInRange(1, 90)(text);
                                },
                              ),
                            ],
                            if (_problem != null) ...[
                              const SizedBox(height: 12),
                              Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
                            ],
                            if (_message != null) ...[
                              const SizedBox(height: 12),
                              Text(_message!, style: const TextStyle(color: Colors.green)),
                            ],
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              key: const ValueKey('desk-issue'),
                              onPressed: _issuing || !refs.ready ? null : _issue,
                              icon: const Icon(Icons.outbox),
                              label: const Text('Выдать'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Книги на руках', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _loansBlock(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loansBlock(ThemeData theme) {
    if (_loading && _loans == null) {
      return const Padding(padding: EdgeInsets.all(24), child: LoadingView());
    }
    if (_loadError != null) {
      return SizedBox(height: 220, child: ErrorView(message: _loadError!, onRetry: _load));
    }
    final loans = _loans ?? const <Loan>[];
    if (loans.isEmpty) {
      return const SizedBox(height: 160, child: EmptyView(message: 'Сейчас нет выданных книг.'));
    }
    return Column(
      children: [
        for (final loan in loans)
          Card(
            child: ListTile(
              key: ValueKey('desk-loan-${loan.id}'),
              leading: Icon(
                loan.status == LoanStatus.overdue ? Icons.warning_amber : Icons.menu_book,
                color: loan.status == LoanStatus.overdue ? theme.colorScheme.error : null,
              ),
              title: Text(loan.bookTitle),
              subtitle: Text(
                '${loan.readerName}\n${loan.status.label} · вернуть до ${_date(loan.dueAt)}',
              ),
              isThreeLine: true,
              trailing: OutlinedButton(
                onPressed: _busyId == null ? () => _return(loan) : null,
                child: const Text('Принять'),
              ),
            ),
          ),
      ],
    );
  }
}
