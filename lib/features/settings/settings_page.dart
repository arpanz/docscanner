import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_prefs.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final pageSize = PdfPageSizeOption.values.firstWhere(
      (option) => option.name == ref.watch(pageSizePreferenceProvider),
      orElse: () => PdfPageSizeOption.a4,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListTile(
            leading: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.dark_mode_outlined
                  : themeMode == ThemeMode.light
                      ? Icons.light_mode_outlined
                      : Icons.brightness_auto_outlined,
            ),
            title: const Text('Theme'),
            subtitle: Text(
              themeMode == ThemeMode.dark
                  ? 'Dark'
                  : themeMode == ThemeMode.light
                      ? 'Light'
                      : 'System default',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeDialog(context, ref, themeMode),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Default PDF page size'),
            subtitle: Text(pageSize.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showPageSizeDialog(context, ref, pageSize),
          ),
          const Divider(),
          const _SectionHeader('Storage'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Clear app cache'),
            subtitle: const Text('Removes generated thumbnails and temporary edit files'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _clearCache(context),
          ),
          const Divider(),
          const _SectionHeader('About'),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '...';
              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                trailing: Text(
                  version,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'DocScanner',
                  applicationVersion: version,
                  applicationLegalese: '\u00a9 2026 DocScanner',
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref, ThemeMode current) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('System default'),
              subtitle: const Text('Follow device theme'),
              value: ThemeMode.system,
              groupValue: current,
              onChanged: (value) {
                if (value != null) {
                  ref.read(themeModeProvider.notifier).setMode(value);
                  Navigator.pop(ctx);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: current,
              onChanged: (value) {
                if (value != null) {
                  ref.read(themeModeProvider.notifier).setMode(value);
                  Navigator.pop(ctx);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: current,
              onChanged: (value) {
                if (value != null) {
                  ref.read(themeModeProvider.notifier).setMode(value);
                  Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPageSizeDialog(
    BuildContext context,
    WidgetRef ref,
    PdfPageSizeOption current,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF page size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: PdfPageSizeOption.values.map((option) {
            return RadioListTile<PdfPageSizeOption>(
              title: Text(option.label),
              value: option,
              groupValue: current,
              onChanged: (value) {
                if (value != null) {
                  ref.read(pageSizePreferenceProvider.notifier).setValue(value.name);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Clear app cache?',
      message:
          'This removes DocScanner temporary files only. Your saved documents will stay intact.',
      confirmLabel: 'Clear',
      destructive: false,
    );
    if (!confirmed) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final deleted = await _deleteKnownCacheEntries(Directory(tempDir.path));
      if (context.mounted) {
        showSnackBar(
          context,
          deleted == 0 ? 'Cache is already empty' : 'Cleared $deleted cached item${deleted == 1 ? '' : 's'}',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(
          context,
          userFacingError(e, fallback: 'Could not clear the app cache.'),
          isError: true,
        );
      }
    }
  }

  Future<int> _deleteKnownCacheEntries(Directory cacheDir) async {
    if (!await cacheDir.exists()) return 0;
    var count = 0;
    await for (final entity in cacheDir.list()) {
      final name = p.basename(entity.path);
      final isKnownFile = entity is File &&
          (name.startsWith('scan_append_') ||
              name.startsWith('scan_') ||
              name.startsWith('ocr_'));
      final isKnownDir = entity is Directory && name == 'pdf_thumbnails';
      if (!isKnownFile && !isKnownDir) continue;
      await entity.delete(recursive: true);
      count++;
    }
    return count;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
