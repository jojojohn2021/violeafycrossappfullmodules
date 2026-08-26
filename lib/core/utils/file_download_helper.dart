import 'dart:typed_data';
import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart' as helper;

/// Triggers a direct PDF file download on Web or native save/share sheet on Mobile/Desktop.
Future<void> downloadPdfFile(Uint8List bytes, String fileName) async {
  await helper.saveAndDownloadPdfBytes(bytes, fileName);
}
