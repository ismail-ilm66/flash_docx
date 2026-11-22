import 'package:flash_dox/app/theme/app_theme.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/scanner/domain/entities/scan_mode_rules.dart';
import 'package:flash_dox/features/scanner/presentation/widgets/camera_overlay.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round 10, P0-2: the camera screen while the camera starts.
void main() {
  var shots = 0;

  Future<void> pump(WidgetTester tester, {required bool ready}) async {
    tester.view
      ..physicalSize = const Size(360, 780)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 24, bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CameraOverlay(
            preview: const ColoredBox(color: Colors.black),
            rules: ScanModeRules.of(ScanMode.document),
            title: 'Document',
            guide: 'Hold the phone flat over the page',
            flashOn: false,
            captureCount: 0,
            canFinish: false,
            showModes: true,
            capturing: false,
            ready: ready,
            onClose: () {},
            onFlash: () {},
            onMode: (_) {},
            onShutter: () => shots++,
            onFinish: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Rect modeBar(WidgetTester tester) => tester.getRect(find.text('Document').last);

  testWidgets('starting: no spinner, the shutter is dimmed and ignores taps, nothing moves when ready', (tester) async {
    shots = 0;
    await pump(tester, ready: false);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final shutter = find.bySemanticsLabel('Take photo');
    await tester.tap(shutter, warnIfMissed: false);
    expect(shots, 0);
    final before = (modeBar(tester), tester.getRect(shutter));

    await pump(tester, ready: true);
    await tester.tap(shutter);
    expect(shots, 1);
    expect((modeBar(tester), tester.getRect(shutter)), before, reason: 'the mode bar and shutter stay put');
  });
}
