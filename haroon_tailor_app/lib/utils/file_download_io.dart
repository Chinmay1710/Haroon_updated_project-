import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

void saveFileToDevice({required String content, required String fileName}) async {
  final bytes = utf8.encode(content);
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Save Backup File',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: Uint8List.fromList(bytes),
  );
  if (uri != null) {
    try {
      final filePath = uri.scheme == 'file' ? uri.toFilePath() : uri.path;
      final file = File(filePath);
      if (!await file.exists()) {
        await file.writeAsBytes(bytes);
      }
    } catch (_) {}
  }
}
