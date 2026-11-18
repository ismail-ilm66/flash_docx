import 'dart:async';

import 'package:flash_dox/app/theme/app_theme.dart';
import 'package:flash_dox/l10n/gen/app_localizations.dart';
import 'package:flash_dox/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Round 7, P0-3: one Back press lost 8 adjusted pages. The app bar's ‹
/// popped the route directly, past the screen's "Discard?" guard.
void main() {
  var discarded = 0;

  Future<void> open(WidgetTester tester) async {
    discarded = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => DiscardScanGuard(
                    guard: true,
                    pageCount: 8,
                    onDiscard: () {
                      discarded++;
                      Navigator.of(context).pop();
                    },
                    child: const AppScaffold(topBar: AppTopBar(title: 'Adjust edges'), body: SizedBox()),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final (how, back) in [
    ('the ‹ in the app bar', (WidgetTester t) => t.tap(find.byTooltip('Back'))),
    ('the system Back button', (WidgetTester t) => t.binding.handlePopRoute()),
  ]) {
    testWidgets('$how asks before discarding', (tester) async {
      await open(tester);
      await back(tester);
      await tester.pumpAndSettle();
      expect(find.text('Discard 8 scans?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust edges'), findsOneWidget);
      expect(discarded, 0);

      await back(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(discarded, 1);
      expect(find.text('open'), findsOneWidget);
    });
  }

  testWidgets('system Back through go_router, after the camera replaced itself with Adjust edges', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/camera', builder: (_, _) => const Scaffold(body: Text('camera'))),
        GoRoute(
          path: '/adjust',
          builder: (context, _) => DiscardScanGuard(
            guard: true,
            pageCount: 3,
            onDiscard: () => context.pop(),
            child: const AppScaffold(topBar: AppTopBar(title: 'Adjust edges'), body: SizedBox()),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    unawaited(router.push('/camera'));
    await tester.pumpAndSettle();
    unawaited(router.pushReplacement('/adjust'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard 3 scans?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
