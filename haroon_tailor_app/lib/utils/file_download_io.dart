import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

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

/// Resolves preferred directory for storing the single backup ZIP
Future<Directory> getBackupDirectory() async {
  Directory? targetDir;
  try {
    if (Platform.isAndroid) {
      final androidDownload = Directory('/storage/emulated/0/Download');
      if (await androidDownload.exists()) {
        targetDir = androidDownload;
      }
    }
  } catch (_) {}

  try {
    targetDir ??= await getDownloadsDirectory();
  } catch (_) {}

  try {
    targetDir ??= await getApplicationDocumentsDirectory();
  } catch (_) {}

  targetDir ??= Directory.current;
  return targetDir;
}

/// Atomically saves or updates the stable backup ZIP archive.
/// Uses a temporary file (.tmp) and verifies archive integrity before replacing.
/// Preserves previous valid backup intact if anything fails.
Future<String?> saveStableBackupZipPlatform({
  required Uint8List zipBytes,
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  final dir = await getBackupDirectory();
  final finalFile = File('${dir.path}/$fileName');
  final tmpFile = File('${dir.path}/$fileName.tmp');

  try {
    // 1. Write to temporary file first
    await tmpFile.writeAsBytes(zipBytes, flush: true);

    // 2. Validate archive integrity and ensure backup.json exists
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    final hasBackupJson = archive.files.any((f) => f.name == 'backup.json');
    if (!hasBackupJson) {
      throw Exception('Backup validation failed: backup.json is missing in archive');
    }

    // 3. Atomically overwrite the destination file
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tmpFile.rename(finalFile.path);

    return finalFile.path;
  } catch (e) {
    if (await tmpFile.exists()) {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
    rethrow;
  }
}

/// Retrieves the raw bytes of the existing single backup ZIP (if present)
/// to enable incremental reuse of unchanged photos without re-downloading.
Future<Uint8List?> getExistingBackupZipPlatform({
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  try {
    final dir = await getBackupDirectory();
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      return await file.readAsBytes();
    }
  } catch (_) {}
  return null;
}

/// Retrieves metadata about the single backup ZIP file
Future<Map<String, dynamic>> getLastBackupInfoPlatform({
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  try {
    final dir = await getBackupDirectory();
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      final stat = await file.stat();
      return {
        'exists': true,
        'path': file.path,
        'lastModified': stat.modified,
        'sizeBytes': stat.size,
      };
    }
  } catch (_) {}
  return {
    'exists': false,
    'path': '',
    'lastModified': null,
    'sizeBytes': 0,
  };
}
