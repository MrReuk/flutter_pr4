import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/permissions.dart';
import '../auth/rights.dart';
import '../models/book.dart';
import '../models/book_query.dart';
import '../state/paged_list_notifier.dart';
import '../state/reference_notifier.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/debounced_text_field.dart';
import '../widgets/entity_list_body.dart';
import '../widgets/entity_table.dart';
import '../widgets/id_dropdown.dart';
import '../widgets/library_scaffold.dart';
import '../widgets/list_toolbar.dart';
import '../widgets/row_actions.dart';
import '../widgets/selection_bar.dart';

class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key, required this.query});

  final BookQuery query;

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  BookQuery get _query => widget.query;

  PagedListNotifier<Book, BookQuery> get _notifier =>
      context.read<PagedListNotifier<Book, BookQuery>>();

  void _go(BookQuery next) => context.go(next.toLocation('/books'));

  BookQuery get _resetQuery => BookQuery(
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
      context.read<ReferenceNotifier>().load();
    });
  }

  @override
  void didUpdateWidget(BookListScreen oldWidget) {
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
    final notifier = context.watch<PagedListNotifier<Book, BookQuery>>();
    final refs = context.watch<ReferenceNotifier>();
    final q = _query;
    final rights = listRights(context, Permission.manageCatalog);

    return LibraryScaffold(
      title: 'Книги',
      body: Column(
        children: [
          ListToolbar(
            search: q.search,
            searchLabel: 'Поиск по названию или ISBN',
            onSearch: (text) => _go(_query.copyWith(search: text)),
            activeFilterCount: q.activeFilterCount,
            initiallyOpen: q.activeFilterCount > 0,
            onReset: () => _go(_resetQuery),
            addLabel: 'Добавить книгу',
            onAdd: rights.canManage ? () => _open('/books/new') : null,
            filters: [
              IdDropdown(
                label: 'Жанр',
                value: q.genreId,
                options: refs.genreOptions(),
                onChanged: (value) => _go(_query.copyWith(genreId: value)),
              ),
              IdDropdown(
                label: 'Издательство',
                value: q.publisherId,
                options: refs.publisherOptions(),
                onChanged: (value) => _go(_query.copyWith(publisherId: value)),
              ),
              SizedBox(
                width: 110,
                child: DebouncedTextField(
                  value: q.yearFrom?.toString() ?? '',
                  onChanged: (text) =>
                      _go(_query.copyWith(yearFrom: int.tryParse(text.trim()))),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Год от',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: DebouncedTextField(
                  value: q.yearTo?.toString() ?? '',
                  onChanged: (text) =>
                      _go(_query.copyWith(yearTo: int.tryParse(text.trim()))),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Год до',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: q.onlyAvailable,
                    onChanged: (value) =>
                        _go(_query.copyWith(onlyAvailable: value)),
                  ),
                  const SizedBox(width: 8),
                  const Text('Только доступные'),
                ],
              ),
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
            child: EntityListBody<Book>(
              status: notifier.status,
              error: notifier.error,
              result: notifier.result,
              onRetry: notifier.load,
              emptyMessage: 'Книги не найдены. Измените поиск или фильтры.',
              onReset: q.search.isNotEmpty || q.activeFilterCount > 0
                  ? () => _go(_resetQuery)
                  : null,
              columns: [
                TableColumnSpec<Book>(
                  label: 'Название',
                  sortField: 'title',
                  build: (b) => CellText(b.title, maxWidth: 280),
                ),
                TableColumnSpec<Book>(
                  label: 'Авторы',
                  build: (b) => CellText(refs.authorNames(b.authorIds)),
                ),
                TableColumnSpec<Book>(
                  label: 'Жанры',
                  build: (b) => CellText(refs.genreNames(b.genreIds), maxWidth: 200),
                ),
                TableColumnSpec<Book>(
                  label: 'Издательство',
                  build: (b) => Text(refs.publisherName(b.publisherId)),
                ),
                TableColumnSpec<Book>(
                  label: 'Год',
                  sortField: 'year',
                  numeric: true,
                  build: (b) => Text('${b.year}'),
                ),
                TableColumnSpec<Book>(
                  label: 'Страниц',
                  sortField: 'pages',
                  numeric: true,
                  build: (b) => Text('${b.pages}'),
                ),
                TableColumnSpec<Book>(
                  label: 'Экз.',
                  numeric: true,
                  build: (b) => Text('${b.copiesAvailable}/${b.copiesTotal}'),
                ),
              ],
              idOf: (b) => b.id,
              isDeleted: (b) => b.isDeleted,
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
              onOpen: (b) => _open('/books/${b.id}'),
              actions: (b) => buildRowActions(
                context,
                deleted: b.isDeleted,
                rights: rights,
                name: b.title,
                onEdit: () => _open('/books/${b.id}/edit'),
                onSoftDelete: () => _afterChange(() => notifier.softDelete(b.id)),
                onHardDelete: () => _afterChange(() => notifier.hardDelete(b.id)),
                onRestore: () => _afterChange(() => notifier.restore(b.id)),
              ),
              titleOf: (b) => b.title,
              subtitleOf: (b) =>
                  '${refs.authorNames(b.authorIds)}\n${b.year} · ${b.pages} стр. · ${refs.publisherName(b.publisherId)}',
              onPage: (page) => _go(_query.copyWith(page: page)),
              onSize: (size) => _go(_query.copyWith(size: size)),
            ),
          ),
        ],
      ),
    );
  }
}
