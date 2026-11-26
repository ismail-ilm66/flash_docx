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

  testWidgets('round 11: A · HD · ⋮ on top, Undo and Done, Document in the middle of the strip, the outline', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 780)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var undos = 0;
    var finished = 0;
    ScanMode? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CameraOverlay(
            preview: const ColoredBox(color: Colors.black),
            rules: ScanModeRules.of(ScanMode.document),
            title: 'Document · 3 pages',
            guide: null,
            flashOn: false,
            captureCount: 3,
            canFinish: true,
            showModes: true,
            capturing: false,
            onClose: () {},
            onFlash: () {},
            onMode: (m) => picked = m,
            onShutter: () {},
            onFinish: () => finished++,
            onUndo: () => undos++,
            onSettings: () {},
            onAutoCapture: () {},
            autoCapture: true,
            onHd: () {},
            outline: Quad.full(inset: 0.2),
            captureProgress: 0.5,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('HD'), findsOneWidget);
    expect(find.bySemanticsLabel('Camera settings'), findsOneWidget);
    // No hint (phone flat), "Page found · hold still" on the outline.
    expect(find.text('Page found · hold still'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Undo'));
    expect(undos, 1);
    await tester.tap(find.text('Done'));
    expect(finished, 1);
    // Document is centred; Passport · ID Card left, Passport photo right.
    final centre = tester.getCenter(find.text('Document')).dx;
    expect(centre, closeTo(180, 2));
    expect(tester.getCenter(find.text('ID card')).dx, lessThan(centre));
    expect(tester.getCenter(find.text('Passport photo')).dx, greaterThan(centre));
    await tester.tap(find.text('ID card'));
    await tester.pumpAndSettle();
    expect(picked, ScanMode.idCard);
    // Auto capture's ring on the shutter.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
