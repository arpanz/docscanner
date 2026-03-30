// lib/features/camera/camera_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_page_native.dart';
import 'camera_page_ios.dart';

/// Cross-platform camera page.
/// 
/// - Android: Uses native CameraX + OpenCV implementation
/// - iOS: Uses flutter_doc_scanner package
class CameraPage extends ConsumerWidget {
  const CameraPage({super.key, this.existingDocId});
  final int? existingDocId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use native implementation on Android
    if (Platform.isAndroid) {
      return CameraPageNative(existingDocId: existingDocId);
    }
    
    // Use flutter_doc_scanner on iOS
    return CameraPageIos(existingDocId: existingDocId);
  }
}
