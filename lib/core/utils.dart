// lib/core/utils.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------
String formatDate(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);
String formatDateTime(DateTime dt) =>
    DateFormat('MMM d, yyyy • h:mm a').format(dt);

/// Returns a human-friendly relative label: "Today", "Yesterday", or a date string.
String relativeDate(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return formatDate(dt);
}

// ---------------------------------------------------------------------------
// File / size helpers
// ---------------------------------------------------------------------------
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Returns the file size in bytes, or 0 if the file doesn't exist.
Future<int> fileSize(String path) async {
  try {
    return await File(path).length();
  } catch (_) {
    return 0;
  }
}

/// Returns the total size of multiple files in bytes.
Future<int> totalFileSize(List<String> paths) async {
  int total = 0;
  for (final path in paths) {
    try {
      total += await File(path).length();
    } catch (_) {}
  }
  return total;
}

/// Cleans a file path by removing 'file://' prefix if present.
/// This ensures consistent file path handling across the app.
String cleanFilePath(String path) {
  if (path.startsWith('file://')) {
    return Uri.parse(path).toFilePath();
  }
  return path;
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------
/// Truncates [text] to [maxLength] characters, appending '…' if needed.
String truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}…';
}

/// Returns initials (up to 2 chars) from a document title.
String initials(String title) {
  final words = title.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return '?';
  if (words.length == 1) return words[0][0].toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------
void showSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
}

String userFacingError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  final text = error.toString().trim().toLowerCase();
  if (text.isEmpty) return fallback;
  if (text.contains('permission')) {
    return 'Permission was denied. Please review app settings and try again.';
  }
  if (text.contains('network')) {
    return 'A network problem interrupted the action. Please try again.';
  }
  if (text.contains('not found')) {
    return 'The requested file could not be found.';
  }
  return fallback;
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class AppProgressOverlay extends StatelessWidget {
  final String message;
  const AppProgressOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 14),
              Material(type: MaterialType.transparency, child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}
