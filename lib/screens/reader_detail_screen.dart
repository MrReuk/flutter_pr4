import 'package:flutter/material.dart';

import '../auth/permissions.dart';
import '../models/reader.dart';
import '../validation/validators.dart';
import '../widgets/detail_layout.dart';
import 'entity_detail_screen.dart';

class ReaderDetailScreen extends StatelessWidget {
  const ReaderDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EntityDetailScreen<Reader>(
      title: 'Карточка читателя',
      editPermission: Permission.manageReaders,
      listPath: '/readers',
      listLabel: 'К списку читателей',
      notFoundMessage: 'Читатель не найден',
      editLocation: (reader) => '/readers/${reader.id}/edit',
      nameOf: (reader) => reader.fullName,
      isDeleted: (reader) => reader.isDeleted,
      fields: (context, reader) {
        final card = reader.card;
        return [
          DetailField(label: 'Почта', child: Text(reader.email)),
          DetailField(
            label: 'Телефон',
            child: Text(reader.phone.isEmpty ? '—' : reader.phone),
          ),
          DetailField(
            label: 'Читательский билет',
            child: card == null
                ? const Text('Билет не оформлен')
                : Card.outlined(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.number),
                          const SizedBox(height: 4),
                          if (card.issuedAt != null)
                            Text('Выдан: ${formatRuDate(card.issuedAt!)}'),
                          if (card.expiresAt != null)
                            Text('Действует до: ${formatRuDate(card.expiresAt!)}'),
                          const SizedBox(height: 8),
                          Chip(
                            label: Text(
                              card.isExpiredAt(DateTime.now())
                                  ? 'Срок действия истёк'
                                  : 'Действует',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ];
      },
    );
  }
}
