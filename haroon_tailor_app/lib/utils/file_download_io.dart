import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import 'package:path_provider/path_provider.dart';

Future<String?> saveFileToDevice({required String content, required String fileName}) async {
  final bytes = utf8.encode(content);
  String? savedPath;

  try {
    Directory? downloadsDir;
    if (Platform.isAndroid) {
      final androidDownload = Directory('/storage/emulated/0/Download');
      if (await androidDownload.exists()) {
        downloadsDir = androidDownload;
      }
    }
    downloadsDir ??= await getDownloadsDirectory();
    downloadsDir ??= await getApplicationDocumentsDirectory();

    final file = File('${downloadsDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    savedPath = file.path;
  } catch (_) {}

  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Backup File',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(bytes),
    );
    if (uri != null) {
      final filePath = uri.scheme == 'file' ? uri.toFilePath() : uri.path;
      final file = File(filePath);
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      savedPath = filePath;
    }
  } catch (_) {}

  return savedPath;
}

Future<String?> saveZipFileToDevice({required Uint8List zipBytes, required String fileName}) async {
  String? savedPath;

  try {
    Directory? downloadsDir;
    if (Platform.isAndroid) {
      final androidDownload = Directory('/storage/emulated/0/Download');
      if (await androidDownload.exists()) {
        downloadsDir = androidDownload;
      }
    }
    downloadsDir ??= await getDownloadsDirectory();
    downloadsDir ??= await getApplicationDocumentsDirectory();

    final file = File('${downloadsDir.path}/$fileName');
    await file.writeAsBytes(zipBytes, flush: true);
    savedPath = file.path;
  } catch (_) {}

  try {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Backup ZIP File',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: zipBytes,
    );
    if (uri != null) {
      final filePath = uri.scheme == 'file' ? uri.toFilePath() : uri.path;
      final file = File(filePath);
      if (!await file.exists()) {
        await file.writeAsBytes(zipBytes, flush: true);
      }
      savedPath = filePath;
    }
  } catch (_) {}

  return savedPath;
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
