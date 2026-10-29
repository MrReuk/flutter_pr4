import 'package:flutter/material.dart';

import '../auth/permissions.dart';
import '../models/reader.dart';
import '../models/simple_query.dart';
import '../validation/validators.dart';
import '../widgets/entity_table.dart';
import 'simple_list_screen.dart';

String _cardLabel(LibraryCard? card) {
  if (card == null) return 'нет';
  final expires = card.expiresAt;
  if (expires == null) return card.number;
  final suffix = card.isExpiredAt(DateTime.now()) ? ' (просрочен)' : '';
  return '${card.number} до ${formatRuDate(expires)}$suffix';
}

class ReaderListScreen extends StatelessWidget {
  const ReaderListScreen({super.key, required this.query});

  final SimpleQuery query;

  @override
  Widget build(BuildContext context) {
    return SimpleListScreen<Reader>(
      query: query,
      config: SimpleListConfig<Reader>(
        managePermission: Permission.manageReaders,
        title: 'Читатели',
        path: '/readers',
        searchLabel: 'Поиск по ФИО, почте или телефону',
        emptyMessage: 'Читатели не найдены. Измените поиск или фильтры.',
        addLabel: 'Добавить читателя',
        columns: (context) => [
          TableColumnSpec<Reader>(
            label: 'ФИО',
            sortField: 'fullName',
            build: (r) => Text(r.fullName),
          ),
          TableColumnSpec<Reader>(
            label: 'Почта',
            sortField: 'email',
            build: (r) => Text(r.email),
          ),
          TableColumnSpec<Reader>(
            label: 'Телефон',
            build: (r) => Text(r.phone.isEmpty ? '—' : r.phone),
          ),
          TableColumnSpec<Reader>(
            label: 'Билет',
            build: (r) => Text(_cardLabel(r.card)),
          ),
        ],
        idOf: (r) => r.id,
        isDeleted: (r) => r.isDeleted,
        nameOf: (r) => r.fullName,
        subtitleOf: (r) => '${r.email}\nБилет: ${_cardLabel(r.card)}',
      ),
    );
  }
}
