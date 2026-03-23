// lib/shared/services/permission_service.dart
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PermissionService {
  /// Request camera permission
  Future<bool> requestCamera() async {
    if (Platform.isAndroid) {
      final status = await Permission.camera.request();
      return status.isGranted;
    }
    // iOS handles permissions via Info.plist
    return true;
  }

  /// Request storage permission (Android only)
  Future<bool> requestStorage() async {
    if (Platform.isAndroid) {
      // For Android 13+, use photos permission
      if (await Permission.photos.request().isGranted) {
        return true;
      }
      
      // For older Android, request storage
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    // iOS handles permissions via Info.plist
    return true;
  }

  /// Check if camera permission is granted
  Future<bool> hasCamera() async {
    return await Permission.camera.isGranted;
  }

  /// Check if storage permission is granted
  Future<bool> hasStorage() async {
    if (Platform.isAndroid) {
      return await Permission.photos.isGranted || 
             await Permission.storage.isGranted;
    }
    return true;
  }

  /// Open app settings if permission denied
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});
