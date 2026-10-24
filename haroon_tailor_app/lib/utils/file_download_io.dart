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

void saveZipFileToDevice({required Uint8List zipBytes, required String fileName}) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Save Backup ZIP File',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['zip'],
    bytes: zipBytes,
  );
  if (uri != null) {
    try {
      final filePath = uri.scheme == 'file' ? uri.toFilePath() : uri.path;
      final file = File(filePath);
      if (!await file.exists()) {
        await file.writeAsBytes(zipBytes);
      }
    } catch (_) {}
  }
}

Future<Uint8List?> pickZipFileFromDevice() async {
  final pickedFiles = await FilePicker.pickFiles(
    dialogTitle: 'Select Haroon Tailor Backup ZIP File',
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  if (pickedFiles.isEmpty) return null;
  return await pickedFiles.first.xFile.readAsBytes();
}

Future<String?> pickJsonFileFromDevice() async {
  final pickedFiles = await FilePicker.pickFiles(
    dialogTitle: 'Select Haroon Tailor Backup JSON File',
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (pickedFiles.isEmpty) return null;
  return await pickedFiles.first.xFile.readAsString();
}
