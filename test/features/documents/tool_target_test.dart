import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/presentation/tools/tool_target.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flutter_test/flutter_test.dart';

/// P1-4: a scan made for a tool goes straight to the tool after Done.
void main() {
  test('a new scan for a tool: Home, its viewer, then the tool', () {
    for (final tool in ToolTarget.values) {
      final r = routeAfterSave(isNewDocument: true, documentId: 'd1', tool: tool);
      expect(r.goHome, Routes.home);
      expect(r.viewer, Routes.viewer('d1'));
      expect(r.tool, tool);
    }
  });

  test('a plain new scan opens its viewer; an edit pops back', () {
    expect(routeAfterSave(isNewDocument: true, documentId: 'd1').tool, isNull);
    final edit = routeAfterSave(isNewDocument: false, documentId: 'd1', tool: ToolTarget.sign);
    expect((edit.goHome, edit.viewer, edit.tool), (null, null, null));
  });

  test('the target survives EditorArgs.copyWith (camera → Adjust → Enhance)', () {
    const args = EditorArgs(pages: [], mode: ScanMode.document, tool: ToolTarget.shrink);
    expect(args.copyWith(initialIndex: 2, startAtEnhance: true).tool, ToolTarget.shrink);
  });
}
