import 'package:flash_dox/app/di/injection.dart';
import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/extensions/context_ext.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/usecases/watch_documents.dart';
import 'package:flash_dox/features/documents/presentation/tools/tool_target.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// What the tool picker returns (round 5, P1-4).
sealed class ToolPick {
  const ToolPick();
}

class PickedDocument extends ToolPick {
  const PickedDocument(this.document);
  final ScanDocument document;
}

/// Scan a new document with the camera, for the tool.
class PickScanNew extends ToolPick {
  const PickScanNew();
}

/// Import from Photos, for the tool.
class PickFromPhotos extends ToolPick {
  const PickFromPhotos();
}

/// The tool picker (P1-4): "Pick a document to sign, or scan a new one",
/// two big buttons (Scan new, From photos), then the user's documents,
/// newest first. Null when dismissed.
Future<ToolPick?> showPickDocumentSheet(
  BuildContext context, {
  required ToolTarget tool,
}) {
  return AppBottomSheet.show<ToolPick>(
    context,
    builder: (_) => _PickDocumentSheet(tool: tool),
  );
}

class _PickDocumentSheet extends StatelessWidget {
  const _PickDocumentSheet({required this.tool});

  final ToolTarget tool;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AppBottomSheet(
      title: switch (tool) {
        ToolTarget.sign => l.pickTitleSign,
        ToolTarget.shrink => l.pickTitleShrink,
        ToolTarget.extractText => l.pickTitleText,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: l.pickScanNew,
                  icon: AppIcons.camera,
                  dense: true,
                  onPressed: () =>
                      Navigator.of(context).pop(const PickScanNew()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  label: l.pickFromPhotos,
                  icon: AppIcons.gallery,
                  dense: true,
                  onPressed: () =>
                      Navigator.of(context).pop(const PickFromPhotos()),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x5),
          SectionLabel(
            l.pickOrDocument,
            padding: const EdgeInsets.only(bottom: Space.x1),
          ),
          _documents(context),
        ],
      ),
    );
  }

  Widget _documents(BuildContext context) {
    final l = context.l10n;
    return StreamBuilder<List<ScanDocument>>(
      stream: getIt<WatchDocuments>()(),
      builder: (context, snap) {
        final docs = [...?snap.data]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(Space.x6),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x6),
            child: Text(
              l.pickDocumentEmpty,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
          );
        }
        return Column(
          children: [
            for (final d in docs)
              DocumentTile(
                document: d,
                compact: true,
                onTap: () => Navigator.of(context).pop(PickedDocument(d)),
              ),
          ],
        );
      },
    );
  }
}
