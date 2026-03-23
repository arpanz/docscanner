// lib/features/settings/settings_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    
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
          const Divider(),
          const _SectionHeader('Storage'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Clear cache'),
            subtitle: const Text('Free up storage space'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _clearCache(context, ref),
          ),
          const Divider(),
          const _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            trailing: const Text('1.0.0', style: TextStyle(color: Colors.grey)),
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
                  ref.read(themeModeProvider.notifier).state = value;
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
                  ref.read(themeModeProvider.notifier).state = value;
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
                  ref.read(themeModeProvider.notifier).state = value;
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

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(tempDir.path);
      
      if (await cacheDir.exists()) {
        int count = 0;
        await for (final entity in cacheDir.list()) {
          if (entity is File) {
            await entity.delete();
            count++;
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
            count++;
          }
        }
        
        if (context.mounted) {
          showSnackBar(context, 'Cleared $count cached items');
        }
      } else {
        if (context.mounted) {
          showSnackBar(context, 'Cache is already empty');
        }
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, 'Failed to clear cache: $e', isError: true);
      }
    }
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
