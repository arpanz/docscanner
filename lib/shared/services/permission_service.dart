// lib/shared/services/permission_service.dart
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PermissionService {
  /// Request camera permission.
  Future<bool> requestCamera() async {
    if (Platform.isAndroid) {
      final status = await Permission.camera.request();
      return status.isGranted;
    }
    return true; // iOS handles via Info.plist
  }

  /// Request storage permission.
  /// On Android 13+ (API 33+), READ_EXTERNAL_STORAGE was removed.
  /// We check whether the storage permission is still requestable
  /// (isDenied = can still prompt) to determine the API level.
  /// On API 33+, Permission.storage returns permanentlyDenied without
  /// prompting, so isDenied is false and we skip the request entirely.
  Future<bool> requestStorage() async {
    if (!Platform.isAndroid) return true;

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isDenied) {
      // API <= 32: request legacy storage permission
      final result = await Permission.storage.request();
      return result.isGranted;
    }
    if (storageStatus.isGranted) return true;

    // API 33+: storage is permanently denied without ever prompting.
    // Use photos permission instead for gallery access.
    final photosStatus = await Permission.photos.status;
    if (photosStatus.isDenied) {
      final result = await Permission.photos.request();
      return result.isGranted;
    }
    return photosStatus.isGranted;
  }

  Future<bool> hasCamera() async => Permission.camera.isGranted;

  Future<bool> hasStorage() async {
    if (Platform.isAndroid) {
      return await Permission.photos.isGranted ||
          await Permission.storage.isGranted;
    }
    return true;
  }

  Future<void> openSettings() async => openAppSettings();
}

final permissionServiceProvider =
    Provider<PermissionService>((ref) => PermissionService());
