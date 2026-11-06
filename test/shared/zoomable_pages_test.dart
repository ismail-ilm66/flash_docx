import 'package:flash_dox/shared/widgets/zoomable_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// P0-5: pinch / double-tap zoom never fights the page swipe.
void main() {
  testWidgets('pinch zooms, swipe is held while zoomed, double-tap resets, then swipe pages', (tester) async {
    final zoom = ZoomController();
    var page = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: ZoomablePages(
            itemCount: 3,
            zoom: zoom,
            onPageChanged: (i) => page = i,
            itemBuilder: (_, i) => ColoredBox(color: Colors.primaries[i], child: Center(child: Text('page $i'))),
          ),
        ),
      ),
    );

    // Pinch out with two fingers around the centre.
    final c = tester.getCenter(find.text('page 0'));
    final a = await tester.startGesture(c - const Offset(20, 0));
    final b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-8, 0));
      await b.moveBy(const Offset(8, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(zoom.scale, greaterThan(2));

    // A swipe while zoomed pans the page instead of changing it.
    await tester.drag(find.byType(ZoomablePages), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(page, 0);

    // Double-tap goes back to fit.
    await tester.tap(find.byType(ZoomablePages));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byType(ZoomablePages));
    await tester.pumpAndSettle();
    expect(zoom.scale, closeTo(1, 0.01));

    // Now a swipe changes page, and the new page starts at 1×.
    await tester.fling(find.byType(ZoomablePages), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(page, 1);
    expect(zoom.scale, closeTo(1, 0.01));
  });

  testWidgets('the zoom pill buttons drive the current page', (tester) async {
    final zoom = ZoomController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: ZoomablePages(itemCount: 1, zoom: zoom, itemBuilder: (_, __) => const ColoredBox(color: Colors.white)),
        ),
      ),
    );
    zoom.zoomIn();
    await tester.pumpAndSettle();
    expect(zoom.scale, closeTo(1.5, 0.01));
    zoom.zoomIn();
    await tester.pumpAndSettle();
    expect(zoom.scale, closeTo(2.25, 0.01));
    zoom.reset();
    await tester.pumpAndSettle();
    expect(zoom.scale, closeTo(1, 0.01));
  });
}
