import 'package:flash_dox/app/router/routes.dart';
import 'package:flash_dox/app/theme/app_theme.dart';
import 'package:flash_dox/features/documents/presentation/pages/home_page.dart';
import 'package:flash_dox/features/documents/presentation/pages/viewer_page.dart';
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart';
import 'package:flash_dox/features/editor/presentation/editor_args.dart';
import 'package:flash_dox/features/editor/presentation/pages/adjust_edges_page.dart';
import 'package:flash_dox/features/editor/presentation/pages/enhance_page.dart';
import 'package:flash_dox/features/ocr/presentation/pages/extracted_text_page.dart';
import 'package:flash_dox/features/photo/presentation/photo_crop_page.dart';
import 'package:flash_dox/features/photo/presentation/photo_sheet_page.dart';
import 'package:flash_dox/features/print_layout/presentation/pages/print_layout_page.dart';
import 'package:flash_dox/features/reduce/presentation/reduce_size_page.dart';
import 'package:flash_dox/features/scanner/presentation/pages/camera_page.dart';
import 'package:flash_dox/features/settings/presentation/pages/settings_page.dart';
import 'package:flash_dox/features/signature/presentation/pages/my_signature_page.dart';
import 'package:flash_dox/features/signature/presentation/pages/sign_document_page.dart';
import 'package:flash_dox/features/splash/presentation/splash_page.dart';
import 'package:flash_dox/shared/widgets/back_guards.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// [initialLocation] is for tests; the app always starts at the splash.
GoRouter buildRouter({String initialLocation = Routes.splash}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: Routes.splash,
        pageBuilder: (_, state) => NoTransitionPage(
          key: state.pageKey,
          child: const SplashPage(),
        ),
      ),
      // Round 11 (Home redesign): no bottom navigation. Home is the root
      // (Back twice leaves the app); Settings opens from its header.
      GoRoute(
        path: Routes.home,
        pageBuilder: (_, state) => NoTransitionPage(
          key: state.pageKey,
          child: const LeaveAppGuard(child: HomePage()),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.settings,
        builder: (_, _) => const SettingsPage(),
      ),
      // Full-screen flows outside the shell (no bottom nav).
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.camera,
        pageBuilder: (_, state) => _fade(
          state,
          _dark(CameraPage(args: state.extra as CameraArgs?)),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.adjust,
        pageBuilder: (_, state) => _fade(
          state,
          _dark(AdjustEdgesPage(args: state.extra! as EditorArgs)),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.enhance,
        pageBuilder: (_, state) => _fade(
          state,
          _dark(EnhancePage(bloc: state.extra! as PageEditorBloc)),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.photoCrop,
        builder: (_, state) => PhotoCropPage(args: state.extra! as PhotoCropArgs),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.reduce,
        builder: (_, state) => ReduceSizePage(source: state.extra! as ReduceSource),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: Routes.signature,
        builder: (_, _) => const MySignaturePage(),
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
            path: 'photos',
            builder: (_, state) => PhotoSheetPage(documentId: state.pathParameters['docId']!),
          ),
          GoRoute(
            path: 'sign',
            builder: (_, state) => SignDocumentPage(
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

/// Camera, Adjust edges and Enhance are always dark, whatever the user's
/// theme. Applied at route level so everything on the screen, not only the
/// scaffold, reads the dark tokens.
Widget _dark(Widget child) => Theme(data: AppTheme.dark, child: child);
