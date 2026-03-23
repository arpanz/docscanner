import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../database/app_database.dart';
import '../../../shared/services/pdf_service.dart';

class ExportSheet extends ConsumerStatefulWidget {
  final Document document;

  const ExportSheet({super.key, required this.document});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Export "${widget.document.name}"',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          _ExportOption(
            icon: Icons.picture_as_pdf,
            label: 'Export as PDF',
            sublabel: 'Creates a multi-page PDF file',
            loading: _exporting,
            onTap: () => _export(context, ExportFormat.pdf),
          ),
          const SizedBox(height: 12),
          _ExportOption(
            icon: Icons.image_outlined,
            label: 'Export as Images',
            sublabel: 'Saves each page as a JPEG',
            loading: false,
            onTap: () => _export(context, ExportFormat.images),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, ExportFormat format) async {
    setState(() => _exporting = true);
    try {
      final pdfService = ref.read(pdfServiceProvider);
      final path = format == ExportFormat.pdf
          ? await pdfService.exportPdf(widget.document.id)
          : await pdfService.exportImages(widget.document.id);

      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $path')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

enum ExportFormat { pdf, images }

class _ExportOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool loading;
  final VoidCallback onTap;

  const _ExportOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 32),
      title: Text(label),
      subtitle: Text(sublabel),
      trailing: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      onTap: loading ? null : onTap,
    );
  }
}
