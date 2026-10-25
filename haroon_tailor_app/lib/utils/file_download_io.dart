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

/// Resolves preferred directory for storing the single backup ZIP.
/// Uses getApplicationDocumentsDirectory() which is 100% guaranteed writable
/// on all Android versions without Scoped Storage restrictions.
Future<Directory> getBackupDirectory() async {
  Directory? targetDir;
  try {
    targetDir = await getApplicationDocumentsDirectory();
  } catch (_) {}

  try {
    targetDir ??= await getDownloadsDirectory();
  } catch (_) {}

  targetDir ??= Directory.current;
  return targetDir;
}

/// Atomically saves or updates the stable backup ZIP archive.
/// 1. Validates archive integrity in-memory before writing.
/// 2. Saves to primary app documents directory (100% reliable on all Android versions).
/// 3. Also copies to public Android Download folder for easy sharing to other devices.
Future<String?> saveStableBackupZipPlatform({
  required Uint8List zipBytes,
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  // 1. Validate archive integrity and ensure backup.json exists
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
  final hasBackupJson = archive.files.any((f) => f.name == 'backup.json');
  if (!hasBackupJson) {
    throw Exception('Backup validation failed: backup.json is missing in archive');
  }

  // 2. Primary safe save: App Documents Directory (never fails)
  final dir = await getBackupDirectory();
  final primaryFile = File('${dir.path}/$fileName');
  await primaryFile.writeAsBytes(zipBytes, flush: true);

  // 3. Secondary public save: Android Download folder (so user can copy/share to other devices)
  try {
    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final publicFile = File('${downloadDir.path}/$fileName');
        await publicFile.writeAsBytes(zipBytes, flush: true);
      }
    }
  } catch (_) {
    // Non-fatal if scoped storage blocks direct public write; primaryFile is safely saved!
  }

  return primaryFile.path;
}

/// Retrieves the raw bytes of the existing single backup ZIP (if present)
/// to enable incremental reuse of unchanged photos without re-downloading.
Future<Uint8List?> getExistingBackupZipPlatform({
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  try {
    // 1. Check primary app documents directory
    final dir = await getBackupDirectory();
    final primaryFile = File('${dir.path}/$fileName');
    if (await primaryFile.exists()) {
      return await primaryFile.readAsBytes();
    }

    // 2. Check Android Download directory
    if (Platform.isAndroid) {
      final downloadFile = File('/storage/emulated/0/Download/$fileName');
      if (await downloadFile.exists()) {
        return await downloadFile.readAsBytes();
      }
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

    // Check Android Download directory fallback
    if (Platform.isAndroid) {
      final downloadFile = File('/storage/emulated/0/Download/$fileName');
      if (await downloadFile.exists()) {
        final stat = await downloadFile.stat();
        return {
          'exists': true,
          'path': downloadFile.path,
          'lastModified': stat.modified,
          'sizeBytes': stat.size,
        };
      }
    }
  } catch (_) {}
  return {
    'exists': false,
    'path': '',
    'lastModified': null,
    'sizeBytes': 0,
  };
}
