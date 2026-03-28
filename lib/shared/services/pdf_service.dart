// lib/shared/services/pdf_service.dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../utils/image_utils.dart';

class PdfService {
  final _uuid = const Uuid();

  /// Build a PDF from a list of image file paths and return the output file.
  /// Uses a unique filename to avoid overwriting a concurrent build for the
  /// same document title.
  Future<File> buildPdf({
    required String title,
    required List<String> imagePaths,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final doc = pw.Document(title: title);

    for (final imgPath in imagePaths) {
      final bytes = await File(imgPath).readAsBytes();
      final image = pw.MemoryImage(bytes);

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (ctx) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }

    final outDir = await getTemporaryDirectory();
    // Fix: add UUID suffix so two rapid builds for the same title don't
    // overwrite each other's temp file before copy completes.
    final uniqueName =
        '${sanitizeFileName(title)}_${_uuid.v4().substring(0, 8)}.pdf';
    final outFile = File(p.join(outDir.path, uniqueName));
    await outFile.writeAsBytes(await doc.save());
    return outFile;
  }

  /// Print a PDF using the system print dialog.
  Future<void> printPdf(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  /// Share a PDF via the OS share sheet.
  Future<void> sharePdf(File pdfFile, {String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(pdfFile.path, mimeType: 'application/pdf')],
        subject: subject,
      ),
    );
  }

  /// Share individual page images.
  Future<void> shareImages(List<String> imagePaths, {String? subject}) async {
    final xFiles = imagePaths
        .map((path) => XFile(path, mimeType: 'image/jpeg'))
        .toList();
    await SharePlus.instance.share(
      ShareParams(files: xFiles, subject: subject),
    );
  }

}

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());
