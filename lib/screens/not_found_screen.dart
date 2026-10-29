import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/library_scaffold.dart';
import '../widgets/state_views.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return LibraryScaffold(
      title: 'Страница не найдена',
      body: EmptyView(
        message: 'Адрес $location не существует',
        actionLabel: 'На главную',
        onAction: () => context.go('/'),
      ),
    );
  }
}
