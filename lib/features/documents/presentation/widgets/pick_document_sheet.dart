import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/watch_documents.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// "Pick a document" (round 4, Tools): the user's documents, newest first.
/// Returns the one tapped, or null when dismissed.
Future<ScanDocument?> showPickDocumentSheet(BuildContext context, {String? title}) {
  return AppBottomSheet.show<ScanDocument>(
    context,
    builder: (_) => _PickDocumentSheet(title: title),
  );
}

class _PickDocumentSheet extends StatelessWidget {
  const _PickDocumentSheet({this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AppBottomSheet(
      title: title ?? l.pickDocumentTitle,
      subtitle: title == null ? null : l.pickDocumentTitle,
      child: StreamBuilder<List<ScanDocument>>(
        stream: getIt<WatchDocuments>()(),
        builder: (context, snap) {
          final docs = [...?snap.data]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(Space.x6),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (docs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x6),
              child: Text(l.pickDocumentEmpty, textAlign: TextAlign.center, style: context.text.bodyMedium),
            );
          }
          return Column(
            children: [
              for (final d in docs)
                DocumentTile(
                  document: d,
                  compact: true,
                  onTap: () => Navigator.of(context).pop(d),
                ),
            ],
          );
        },
      ),
    );
  }
}
