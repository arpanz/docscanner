// lib/core/router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:docscanner/features/camera/camera_page.dart';
import 'package:docscanner/features/manager/document_manager_page.dart';
import 'package:docscanner/features/viewer/document_viewer_page.dart';
import 'package:docscanner/features/settings/settings_page.dart';

// ---------------------------------------------------------------------------
// Route paths
// ---------------------------------------------------------------------------
class AppRoutes {
  AppRoutes._();

  static const String manager = '/';
  static const String camera = '/camera';
  static const String viewer = '/viewer/:docId';
  static const String settings = '/settings';

  static String viewerPath(int docId) => '/viewer/$docId';
}

// ---------------------------------------------------------------------------
// Router provider
// ---------------------------------------------------------------------------
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.manager,
    debugLogDiagnostics: false,
    navigatorKey: GlobalKey<NavigatorState>(),
    routes: [
      GoRoute(
        path: AppRoutes.manager,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: DocumentManagerPage()),
      ),
      GoRoute(
        path: AppRoutes.camera,
        pageBuilder: (context, state) {
          final docId = int.tryParse(state.uri.queryParameters['docId'] ?? '');
          return MaterialPage(child: CameraPage(existingDocId: docId));
        },
      ),
      GoRoute(
        path: AppRoutes.viewer,
        pageBuilder: (context, state) {
          final docId = int.parse(state.pathParameters['docId']!);
          return MaterialPage(child: DocumentViewerPage(docId: docId));
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SettingsPage()),
      ),
    ],
    errorPageBuilder: (context, state) => MaterialPage(
      child: Scaffold(
        body: Center(child: Text('Page not found: ${state.uri}')),
      ),
    ),
  );
});
