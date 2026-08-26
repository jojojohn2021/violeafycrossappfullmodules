import 'dart:typed_data';
import 'package:printing/printing.dart';

/// Downloads/Saves PDF bytes on mobile and desktop platforms via the native share/save sheet.
Future<void> saveAndDownloadPdfBytes(Uint8List bytes, String fileName) async {
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}
