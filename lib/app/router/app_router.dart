import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/features/documents/presentation/pages/home_page.dart';
import 'package:flash_dox/features/documents/presentation/pages/viewer_page.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/editor/presentation/pages/adjust_edges_page.dart';
import 'package:flash_dox/features/editor/presentation/pages/enhance_page.dart';
import 'package:flash_dox/features/ocr/presentation/pages/extracted_text_page.dart';
import 'package:flash_dox/features/print_layout/presentation/pages/print_layout_page.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/features/settings/presentation/pages/settings_page.dart';
import 'package:flash_dox/features/splash/presentation/splash_page.dart';
import 'package:flash_dox/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    routes: [
      GoRoute(
        path: Routes.splash,
        pageBuilder: (_, state) => NoTransitionPage(
          key: state.pageKey,
          child: const SplashPage(),
        ),
      ),
      // Bottom-nav shell. The active tab follows the current branch index.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                pageBuilder: (_, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const HomePage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                pageBuilder: (_, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const SettingsPage(),
                ),
              ),
            ],
          ),
        ],
      ),
      // Full-screen flows outside the shell (no bottom nav).
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.camera,
        pageBuilder: (_, state) => _fade(
          state,
          CameraPage(args: state.extra as CameraArgs?),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.adjust,
        pageBuilder: (_, state) => _fade(
          state,
          AdjustEdgesPage(args: state.extra! as EditorArgs),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.enhance,
        pageBuilder: (_, state) => _fade(
          state,
          EnhancePage(bloc: state.extra! as PageEditorBloc),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.viewerPattern,
        builder: (_, state) =>
            ViewerPage(documentId: state.pathParameters['docId']!),
        routes: [
          GoRoute(
            path: 'text',
            builder: (_, state) => ExtractedTextPage(
              documentId: state.pathParameters['docId']!,
              initialPageId: state.uri.queryParameters['page'],
            ),
          ),
          GoRoute(
            path: 'print',
            builder: (_, state) => PrintLayoutPage(
              documentId: state.pathParameters['docId']!,
            ),
          ),
        ],
      ),
    ],
  );
}

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}
