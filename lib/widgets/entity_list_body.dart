import 'package:flutter/material.dart';

import '../models/page_result.dart';
import '../state/load_status.dart';
import 'entity_table.dart';
import 'pagination_bar.dart';
import 'state_views.dart';

class EntityListBody<T> extends StatelessWidget {
  const EntityListBody({
    super.key,
    required this.status,
    required this.error,
    required this.result,
    required this.onRetry,
    required this.emptyMessage,
    required this.onReset,
    required this.columns,
    required this.idOf,
    required this.isDeleted,
    required this.selected,
    required this.onToggleSelect,
    required this.onSelectAll,
    required this.sortField,
    required this.sortAscending,
    required this.onSort,
    required this.actions,
    required this.titleOf,
    required this.subtitleOf,
    required this.onPage,
    required this.onSize,
    this.onOpen,
  });

  final LoadStatus status;
  final String? error;
  final PageResult<T> result;
  final VoidCallback onRetry;
  final String emptyMessage;
  final VoidCallback? onReset;
  final List<TableColumnSpec<T>> columns;
  final int Function(T item) idOf;
  final bool Function(T item) isDeleted;
  final Set<int> selected;
  final ValueChanged<int>? onToggleSelect;
  final ValueChanged<bool>? onSelectAll;
  final String sortField;
  final bool sortAscending;
  final void Function(String field) onSort;
  final void Function(T item)? onOpen;
  final List<Widget> Function(T item) actions;
  final String Function(T item) titleOf;
  final String Function(T item) subtitleOf;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onSize;

  @override
  Widget build(BuildContext context) {
    final hasData = result.items.isNotEmpty;

    if (status == LoadStatus.error) {
      return ErrorView(message: error ?? 'Неизвестная ошибка', onRetry: onRetry);
    }
    if (!hasData && status != LoadStatus.success) {
      return const LoadingView();
    }
    if (!hasData && result.total > 0) {
      return EmptyView(
        message: 'На этой странице нет записей.',
        actionLabel: 'К первой странице',
        onAction: () => onPage(1),
      );
    }
    if (!hasData) {
      return EmptyView(message: emptyMessage, onAction: onReset);
    }

    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Column(
      children: [
        if (status == LoadStatus.loading)
          const LinearProgressIndicator()
        else
          const SizedBox(height: 4),
        Expanded(
          child: narrow
              ? _CardList<T>(
                  items: result.items,
                  columns: columns,
                  idOf: idOf,
                  isDeleted: isDeleted,
                  selected: selected,
                  onToggleSelect: onToggleSelect,
                  sortField: sortField,
                  sortAscending: sortAscending,
                  onSort: onSort,
                  onOpen: onOpen,
                  actions: actions,
                  titleOf: titleOf,
                  subtitleOf: subtitleOf,
                )
              : EntityTable<T>(
                  columns: columns,
                  items: result.items,
                  idOf: idOf,
                  selected: selected,
                  onToggleSelect: onToggleSelect,
                  onSelectAll: onSelectAll,
                  sortField: sortField,
                  sortAscending: sortAscending,
                  onSort: onSort,
                  actions: actions,
                  onOpen: onOpen,
                  isDeleted: isDeleted,
                ),
        ),
        const Divider(height: 1),
        PaginationBar(result: result, onPage: onPage, onSize: onSize),
      ],
    );
  }
}

class _CardList<T> extends StatelessWidget {
  const _CardList({
    required this.items,
    required this.columns,
    required this.idOf,
    required this.isDeleted,
    required this.selected,
    required this.onToggleSelect,
    required this.sortField,
    required this.sortAscending,
    required this.onSort,
    required this.actions,
    required this.titleOf,
    required this.subtitleOf,
    this.onOpen,
  });

  final List<T> items;
  final List<TableColumnSpec<T>> columns;
  final int Function(T item) idOf;
  final bool Function(T item) isDeleted;
  final Set<int> selected;
  final ValueChanged<int>? onToggleSelect;
  final String sortField;
  final bool sortAscending;
  final void Function(String field) onSort;
  final void Function(T item)? onOpen;
  final List<Widget> Function(T item) actions;
  final String Function(T item) titleOf;
  final String Function(T item) subtitleOf;

  @override
  Widget build(BuildContext context) {
    final sortable = columns.where((c) => c.sortField != null).toList();
    final currentSort = sortable.any((c) => c.sortField == sortField) ? sortField : null;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Сортировка:'),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: currentSort,
                  items: [
                    for (final column in sortable)
                      DropdownMenuItem<String>(
                        value: column.sortField!,
                        child: Text(column.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onSort(value);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Направление сортировки',
                icon: Icon(
                  sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                ),
                onPressed: () => onSort(sortField),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final id = idOf(item);
              final deleted = isDeleted(item);
              return Card(
                child: InkWell(
                  onTap: onOpen == null ? null : () => onOpen!(item),
                  child: Row(
                    children: [
                      if (onToggleSelect != null)
                        Checkbox(
                          value: selected.contains(id),
                          onChanged: (_) => onToggleSelect!(id),
                        )
                      else
                        const SizedBox(width: 16),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Opacity(
                            opacity: deleted ? 0.5 : 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titleOf(item),
                                  style: textTheme.titleMedium?.copyWith(
                                    decoration: deleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(subtitleOf(item), style: textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ...actions(item),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
