import 'package:flash_dox/app/theme/app_tokens.dart';
import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// One scrollable gallery of every §12 widget, rendered in light and dark.
class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final doc = ScanDocument(
      id: 'd',
      title: 'Electricity bill March',
      mode: ScanMode.single,
      pages: const [
        ScanPage(id: 'p', documentId: 'd', originalPath: '/none.jpg', edits: PageEdits(), order: 0),
      ],
      createdAt: DateTime(2025, 3, 2, 14, 31),
      updatedAt: DateTime(2025, 3, 2, 14, 31),
      lastActivity: Activity(id: 'a', documentId: 'd', type: ActivityType.sharedPdf, at: DateTime(2025, 3, 2, 14, 31)),
    );
    return ListView(
      padding: const EdgeInsets.all(Space.x4),
      children: [
        DocumentTile(document: doc, onTap: () {}, onMore: () {}),
        const SizedBox(height: Space.x3),
        Row(
          children: [
            Expanded(child: QuickActionTile(icon: AppIcons.single, label: 'Single', onTap: () {})),
            const SizedBox(width: Space.x2),
            Expanded(child: QuickActionTile(icon: AppIcons.idCard, label: 'ID card', onTap: () {})),
          ],
        ),
        const SizedBox(height: Space.x3),
        SegmentedPills<int>(values: const [0, 1, 2], selected: 1, labelOf: (v) => ['System', 'Light', 'Dark'][v], onChanged: (_) {}),
        const SizedBox(height: Space.x3),
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            OptionChip(label: 'Standard', selected: true, onTap: () {}),
            OptionChip(label: 'High quality', selected: false, gated: true, onTap: () {}),
          ],
        ),
        const SizedBox(height: Space.x3),
        OptionCard(title: 'Double-sided PDF', subtitle: 'Flip on long edge', icon: AppIcons.pdf, selected: true, gated: true, onTap: () {}),
        const SizedBox(height: Space.x3),
        LabeledSlider(label: 'Brightness', value: 20, onChanged: (_) {}),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ToolbarAction(icon: AppIcons.rotateLeft, label: 'Rotate', onPressed: () {}),
            ToolbarAction(icon: AppIcons.autoEdges, label: 'Auto', active: true, onPressed: () {}),
            ToolbarAction(icon: AppIcons.delete, label: 'Delete', destructive: true, onPressed: () {}),
            const ToolbarAction(icon: AppIcons.print, label: 'Print', onPressed: null),
          ],
        ),
        const SizedBox(height: Space.x3),
        PrimaryButton(label: 'Share', icon: AppIcons.share, onPressed: () {}),
        const SizedBox(height: Space.x2),
        SecondaryButton(label: 'Save to phone', icon: AppIcons.save, onPressed: () {}),
        const SizedBox(height: Space.x2),
        const PrimaryButton(label: 'Loading', onPressed: null, loading: true),
        const SizedBox(height: Space.x3),
        const Row(
          children: [
            PageThumb(path: null, number: 1, selected: true),
            SizedBox(width: Space.x2),
            PageThumb(path: null, number: 2),
          ],
        ),
        const SizedBox(height: Space.x3),
        const SizedBox(height: 280, child: EmptyState(title: 'No scans yet', body: 'Tap the camera button to scan.')),
        const SizedBox(height: 260, child: ErrorView(failure: StorageFailure())),
      ],
    );
  }
}

void main() {
  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('shared widgets gallery ($name)', (tester) async {
      await tester.pumpApp(const _Gallery(), dark: dark, size: const Size(390, 1400));
      await expectLater(find.byType(_Gallery), matchesGoldenFile('goldens/widgets_gallery_$name.png'));
    });
  }

  testWidgets('AppDialog.confirm resolves true on primary', (tester) async {
    late Future<bool> result;
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => result = AppDialog.confirm(context, title: 'Delete?', body: 'Sure', confirmLabel: 'Delete', destructive: true),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('AppDialog.prompt returns trimmed text', (tester) async {
    late Future<String?> result;
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => result = AppDialog.prompt(context, title: 'Rename', hint: 'Name', confirmLabel: 'Save', initial: 'Old'),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  New name ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await result, 'New name');
  });

  testWidgets('SegmentedPills reports taps', (tester) async {
    int? got;
    await tester.pumpApp(
      SegmentedPills<int>(values: const [1, 2], selected: 1, labelOf: (v) => 'v$v', onChanged: (v) => got = v),
    );
    await tester.tap(find.text('v2'));
    expect(got, 2);
  });
}
