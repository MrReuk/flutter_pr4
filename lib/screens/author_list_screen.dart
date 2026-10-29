import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/permissions.dart';
import '../auth/rights.dart';
import '../models/author.dart';
import '../models/author_query.dart';
import '../state/paged_list_notifier.dart';
import '../state/reference_notifier.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/entity_list_body.dart';
import '../widgets/entity_table.dart';
import '../widgets/library_scaffold.dart';
import '../widgets/list_toolbar.dart';
import '../widgets/row_actions.dart';
import '../widgets/selection_bar.dart';

class AuthorListScreen extends StatefulWidget {
  const AuthorListScreen({super.key, required this.query});

  final AuthorQuery query;

  @override
  State<AuthorListScreen> createState() => _AuthorListScreenState();
}

class _AuthorListScreenState extends State<AuthorListScreen> {
  AuthorQuery get _query => widget.query;

  PagedListNotifier<Author, AuthorQuery> get _notifier =>
      context.read<PagedListNotifier<Author, AuthorQuery>>();

  void _go(AuthorQuery next) => context.go(next.toLocation('/authors'));

  AuthorQuery get _resetQuery => AuthorQuery(
        size: _query.size,
        sortField: _query.sortField,
        sortAscending: _query.sortAscending,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier.applyQuery(widget.query, force: true);
    });
  }

  @override
  void didUpdateWidget(AuthorListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _notifier.applyQuery(widget.query);
      });
    }
  }

  Future<void> _open(String location) async {
    final changed = await context.push<bool>(location);
    if (changed != true || !mounted) return;
    await _notifier.load();
    if (mounted) context.read<ReferenceNotifier>().load();
  }

  Future<String?> _afterChange(Future<String?> Function() operation) async {
    final problem = await operation();
    if (problem == null && mounted) context.read<ReferenceNotifier>().load();
    return problem;
  }

  Future<void> _deleteSelected() async {
    final notifier = _notifier;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAction(
      context,
      title: 'Удалить выбранные записи?',
      message:
          'Будет удалено записей: ${notifier.selected.length}. Их можно восстановить.',
    );
    if (!confirmed) return;
    final summary = await notifier.deleteSelected();
    if (mounted) context.read<ReferenceNotifier>().load();
    final failure = summary.error;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure != null
              ? 'Не удалось удалить записи: $failure'
              : 'Удалено записей: ${summary.deleted}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PagedListNotifier<Author, AuthorQuery>>();
    final q = _query;
    final rights = listRights(context, Permission.manageCatalog);

    return LibraryScaffold(
      title: 'Авторы',
      body: Column(
        children: [
          ListToolbar(
            search: q.search,
            searchLabel: 'Поиск по имени или стране',
            onSearch: (text) => _go(_query.copyWith(search: text)),
            activeFilterCount: q.activeFilterCount,
            initiallyOpen: q.activeFilterCount > 0,
            onReset: () => _go(_resetQuery),
            addLabel: 'Добавить автора',
            onAdd: rights.canManage ? () => _open('/authors/new') : null,
            filters: [
              if (rights.canRestore)
                DeletedSwitch(
                  value: q.includeDeleted,
                  onChanged: (value) => _go(_query.copyWith(includeDeleted: value)),
                ),
            ],
          ),
          if (notifier.hasSelection)
            SelectionBar(
              count: notifier.selected.length,
              onDelete: _deleteSelected,
              onClear: notifier.clearSelection,
            ),
          Expanded(
            child: EntityListBody<Author>(
              status: notifier.status,
              error: notifier.error,
              result: notifier.result,
              onRetry: notifier.load,
              emptyMessage: 'Авторы не найдены. Измените поиск или фильтры.',
              onReset: q.search.isNotEmpty || q.activeFilterCount > 0
                  ? () => _go(_resetQuery)
                  : null,
              columns: [
                TableColumnSpec<Author>(
                  label: 'ФИО',
                  sortField: 'fullName',
                  build: (a) => Text(a.fullName),
                ),
                TableColumnSpec<Author>(
                  label: 'Страна',
                  sortField: 'country',
                  build: (a) => Text(a.country.isEmpty ? '—' : a.country),
                ),
                TableColumnSpec<Author>(
                  label: 'Год рождения',
                  sortField: 'birthYear',
                  numeric: true,
                  build: (a) => Text(a.birthYear == null ? '—' : '${a.birthYear}'),
                ),
              ],
              idOf: (a) => a.id,
              isDeleted: (a) => a.isDeleted,
              selected: notifier.selected,
              onToggleSelect: rights.canManage ? notifier.toggleSelection : null,
              onSelectAll: rights.canManage ? notifier.setAllSelected : null,
              sortField: q.sortField,
              sortAscending: q.sortAscending,
              onSort: (field) => _go(
                _query.copyWith(
                  sortField: field,
                  sortAscending:
                      field == _query.sortField ? !_query.sortAscending : true,
                ),
              ),
              onOpen: (a) => _open('/authors/${a.id}'),
              actions: (a) => buildRowActions(
                context,
                deleted: a.isDeleted,
                rights: rights,
                name: a.fullName,
                onEdit: () => _open('/authors/${a.id}/edit'),
                onSoftDelete: () => _afterChange(() => notifier.softDelete(a.id)),
                onHardDelete: () => _afterChange(() => notifier.hardDelete(a.id)),
                onRestore: () => _afterChange(() => notifier.restore(a.id)),
              ),
              titleOf: (a) => a.fullName,
              subtitleOf: (a) => [
                if (a.country.isNotEmpty) a.country,
                if (a.birthYear != null) '${a.birthYear} г. рождения',
              ].join(' · '),
              onPage: (page) => _go(_query.copyWith(page: page)),
              onSize: (size) => _go(_query.copyWith(size: size)),
            ),
          ),
        ],
      ),
    );
  }
}
