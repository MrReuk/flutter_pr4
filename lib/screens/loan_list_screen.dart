import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/permissions.dart';
import '../models/loan.dart';
import '../models/simple_query.dart';
import '../repositories/entity_repository.dart';
import '../state/paged_list_notifier.dart';
import '../validation/validators.dart';
import '../widgets/choice_dropdown.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/entity_table.dart';
import 'simple_list_screen.dart';

String _date(DateTime? value) => value == null ? '—' : formatRuDate(value);

class LoanListScreen extends StatelessWidget {
  const LoanListScreen({super.key, required this.query});

  final SimpleQuery query;

  @override
  Widget build(BuildContext context) {
    return SimpleListScreen<Loan>(
      query: query,
      config: SimpleListConfig<Loan>(
        managePermission: Permission.manageLoans,
        title: 'Выдачи',
        path: '/loans',
        searchLabel: '',
        searchable: false,
        editable: false,
        openable: false,
        emptyMessage: 'Выдачи не найдены. Измените фильтры.',
        addLabel: 'Оформить выдачу',
        filterBuilder: (context, q, apply) => [
          ChoiceDropdown(
            label: 'Состояние',
            value: q.filter,
            choices: [
              for (final status in LoanStatus.values)
                (value: status.name, label: status.label),
            ],
            onChanged: (value) => apply(q.copyWith(filter: value)),
          ),
        ],
        columns: (context) => [
          TableColumnSpec<Loan>(
            label: 'Читатель',
            build: (l) => Text(l.readerName),
          ),
          TableColumnSpec<Loan>(
            label: 'Книга',
            build: (l) => CellText(l.bookTitle, maxWidth: 280),
          ),
          TableColumnSpec<Loan>(
            label: 'Выдана',
            sortField: 'issuedAt',
            build: (l) => Text(_date(l.issuedAt)),
          ),
          TableColumnSpec<Loan>(
            label: 'Вернуть до',
            sortField: 'dueAt',
            build: (l) => Text(_date(l.dueAt)),
          ),
          TableColumnSpec<Loan>(
            label: 'Возвращена',
            sortField: 'returnedAt',
            build: (l) => Text(_date(l.returnedAt)),
          ),
          TableColumnSpec<Loan>(
            label: 'Состояние',
            build: (l) => Text(l.status.label),
          ),
        ],
        idOf: (l) => l.id,
        isDeleted: (l) => l.isDeleted,
        nameOf: (l) => '${l.bookTitle} — ${l.readerName}',
        subtitleOf: (l) =>
            '${l.readerName}\n${l.status.label} · до ${_date(l.dueAt)}',
        extraActions: (context, loan, reload) => [
          if (!loan.isClosed && !loan.isDeleted)
            IconButton(
              tooltip: 'Принять книгу',
              icon: const Icon(Icons.assignment_return_outlined),
              onPressed: () async {
                final loans = context.read<LoanRepository>();
                try {
                  await loans.markReturned(loan.id);
                } catch (e) {
                  if (!context.mounted) return;
                  await showNotice(
                    context,
                    title: 'Действие невозможно',
                    message: describeError(e),
                  );
                }
                await reload();
              },
            ),
        ],
      ),
    );
  }
}
