import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/presentation/max_size_sheet.dart';
import 'package:flash_dox/features/export/presentation/share_sheet.dart';
import 'package:flash_dox/features/signature/presentation/pages/sign_document_page.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// A Home tool a new scan is made for (round 5, P1-4): after Done the scan
/// goes straight to the tool instead of the viewer.
enum ToolTarget { sign, shrink, extractText }

/// Opens [tool] on [doc]: Sign a document, Max file size → Share, or
/// Extracted text.
Future<void> openTool(BuildContext context, ToolTarget tool, ScanDocument doc) async {
  switch (tool) {
    case ToolTarget.sign:
      await openSignFlow(context, doc.id);
    case ToolTarget.shrink:
      final limit = await showMaxSizeSheet(context, 500000);
      if (limit == null || !context.mounted) return;
      await showShareSheet(
        context,
        doc,
        options: (o) => o.copyWith(format: ExportFormat.pdf, layout: ExportLayout.separate, maxBytes: limit.bytes),
      );
    case ToolTarget.extractText:
      await context.push(Routes.text(doc.id));
  }
}

/// Where a saved scan goes (P1-4): a new scan opens its viewer (Home
/// underneath, so Back works), then its tool if it was made for one; edits
/// of a saved document pop back to the viewer.
({String? goHome, String? viewer, ToolTarget? tool}) routeAfterSave({
  required bool isNewDocument,
  required String documentId,
  ToolTarget? tool,
}) {
  if (!isNewDocument) return (goHome: null, viewer: null, tool: null);
  return (goHome: Routes.home, viewer: Routes.viewer(documentId), tool: tool);
}
