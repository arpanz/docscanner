// lib/core/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/manager/document_manager_page.dart';
import '../features/camera/camera_page.dart';
import '../features/viewer/document_viewer_page.dart';

// ---------------------------------------------------------------------------
// Route paths
// ---------------------------------------------------------------------------
class AppRoutes {
  AppRoutes._();

  static const String manager = '/';
  static const String camera = '/camera';
  static const String viewer = '/viewer/:docId';

  static String viewerPath(int docId) => '/viewer/$docId';
}

// ---------------------------------------------------------------------------
// Router provider
// ---------------------------------------------------------------------------
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.manager,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: AppRoutes.manager,
        pageBuilder: (context, state) => const NoTransitionPage(
          child: DocumentManagerPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.camera,
        pageBuilder: (context, state) {
          final docId = int.tryParse(
            state.uri.queryParameters['docId'] ?? '',
          );
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
    ],
    errorPageBuilder: (context, state) => MaterialPage(
      child: Scaffold(
        body: Center(child: Text('Page not found: ${state.uri}')),
      ),
    ),
  );
});
