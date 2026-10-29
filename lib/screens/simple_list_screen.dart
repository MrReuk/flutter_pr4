import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/permissions.dart';
import '../auth/rights.dart';
import '../models/simple_query.dart';
import '../state/paged_list_notifier.dart';
import '../state/reference_notifier.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/entity_list_body.dart';
import '../widgets/entity_table.dart';
import '../widgets/library_scaffold.dart';
import '../widgets/list_toolbar.dart';
import '../widgets/row_actions.dart';
import '../widgets/selection_bar.dart';

typedef FilterBuilder = List<Widget> Function(
  BuildContext context,
  SimpleQuery query,
  ValueChanged<SimpleQuery> apply,
);

class SimpleListConfig<T> {
  const SimpleListConfig({
    required this.title,
    required this.path,
    required this.searchLabel,
    required this.emptyMessage,
    required this.addLabel,
    required this.columns,
    required this.idOf,
    required this.isDeleted,
    required this.nameOf,
    required this.subtitleOf,
    this.filterBuilder,
    this.searchable = true,
    this.editable = true,
    this.openable = true,
    this.managePermission = Permission.manageCatalog,
    this.extraActions,
  });

  final String title;
  final String path;
  final String searchLabel;
  final String emptyMessage;
  final String addLabel;
  final List<TableColumnSpec<T>> Function(BuildContext context) columns;
  final int Function(T item) idOf;
  final bool Function(T item) isDeleted;
  final String Function(T item) nameOf;
  final String Function(T item) subtitleOf;
  final FilterBuilder? filterBuilder;
  final bool searchable;
  final bool editable;
  final bool openable;
  final Permission managePermission;
  final List<Widget> Function(
    BuildContext context,
    T item,
    Future<void> Function() reload,
  )? extraActions;
}

class SimpleListScreen<T> extends StatefulWidget {
  const SimpleListScreen({super.key, required this.query, required this.config});

  final SimpleQuery query;
  final SimpleListConfig<T> config;

  @override
  State<SimpleListScreen<T>> createState() => _SimpleListScreenState<T>();
}

class _SimpleListScreenState<T> extends State<SimpleListScreen<T>> {
  SimpleListConfig<T> get _config => widget.config;
  SimpleQuery get _query => widget.query;

  PagedListNotifier<T, SimpleQuery> get _notifier =>
      context.read<PagedListNotifier<T, SimpleQuery>>();

  void _go(SimpleQuery next) => context.go(next.toLocation(_config.path));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier.applyQuery(widget.query, force: true);
      context.read<ReferenceNotifier>().load();
    });
  }

  @override
  void didUpdateWidget(SimpleListScreen<T> oldWidget) {
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
    final skipped = summary.requested - summary.deleted;
    final failure = summary.error;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure != null
              ? 'Не удалось удалить записи: $failure'
              : skipped > 0
                  ? 'Удалено записей: ${summary.deleted} из ${summary.requested}. Остальные нельзя удалить: с ними связаны другие записи.'
                  : 'Удалено записей: ${summary.deleted}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PagedListNotifier<T, SimpleQuery>>();
    final q = _query;
    final config = _config;
    final rights = listRights(context, config.managePermission);

    return LibraryScaffold(
      title: config.title,
      body: Column(
        children: [
          ListToolbar(
            search: q.search,
            searchLabel: config.searchLabel,
            showSearch: config.searchable,
            onSearch: (text) => _go(q.copyWith(search: text)),
            activeFilterCount: q.activeFilterCount,
            initiallyOpen: q.activeFilterCount > 0,
            onReset: () => _go(q.reset()),
            addLabel: config.addLabel,
            onAdd: rights.canManage ? () => _open('${config.path}/new') : null,
            filters: [
              ...?config.filterBuilder?.call(context, q, _go),
              if (rights.canRestore)
                DeletedSwitch(
                  value: q.includeDeleted,
                  onChanged: (value) => _go(q.copyWith(includeDeleted: value)),
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
            child: EntityListBody<T>(
              status: notifier.status,
              error: notifier.error,
              result: notifier.result,
              onRetry: notifier.load,
              emptyMessage: config.emptyMessage,
              onReset: q.search.isNotEmpty || q.activeFilterCount > 0
                  ? () => _go(q.reset())
                  : null,
              columns: config.columns(context),
              idOf: config.idOf,
              isDeleted: config.isDeleted,
              selected: notifier.selected,
              onToggleSelect: rights.canManage ? notifier.toggleSelection : null,
              onSelectAll: rights.canManage ? notifier.setAllSelected : null,
              sortField: q.sortField,
              sortAscending: q.sortAscending,
              onSort: (field) => _go(
                q.copyWith(
                  sortField: field,
                  sortAscending: field == q.sortField ? !q.sortAscending : true,
                ),
              ),
              onOpen: config.openable
                  ? (item) => _open('${config.path}/${config.idOf(item)}')
                  : null,
              actions: (item) {
                final id = config.idOf(item);
                return buildRowActions(
                  context,
                  deleted: config.isDeleted(item),
                  rights: rights,
                  name: config.nameOf(item),
                  onEdit: config.editable
                      ? () => _open('${config.path}/$id/edit')
                      : null,
                  extra: config.extraActions?.call(context, item, notifier.load) ??
                      const [],
                  onSoftDelete: () => _afterChange(() => notifier.softDelete(id)),
                  onHardDelete: () => _afterChange(() => notifier.hardDelete(id)),
                  onRestore: () => _afterChange(() => notifier.restore(id)),
                );
              },
              titleOf: config.nameOf,
              subtitleOf: config.subtitleOf,
              onPage: (page) => _go(q.copyWith(page: page)),
              onSize: (size) => _go(q.copyWith(size: size)),
            ),
          ),
        ],
      ),
    );
  }
}
