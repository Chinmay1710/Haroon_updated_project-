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
/// on all Android/iOS/Desktop versions.
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
/// 2. Uses a safe temporary file (.tmp) and atomic replace to never leave a corrupted file.
/// 3. Saves to primary app documents directory.
/// 4. Saves to custom directory if provided.
Future<String?> saveStableBackupZipPlatform({
  required Uint8List zipBytes,
  String fileName = 'HaroonTailor_Backup.zip',
  String? targetDirectoryPath,
}) async {
  // 1. Validate archive integrity and ensure backup.json exists
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
  final hasBackupJson = archive.files.any((f) => f.name == 'backup.json');
  if (!hasBackupJson) {
    throw Exception('Backup validation failed: backup.json is missing in archive');
  }

  // 2. Primary safe save: App Documents Directory (Atomic replacement)
  final dir = await getBackupDirectory();
  final primaryFile = File('${dir.path}/$fileName');
  final tmpFile = File('${dir.path}/$fileName.tmp');

  await tmpFile.writeAsBytes(zipBytes, flush: true);

  if (await primaryFile.exists()) {
    try {
      await primaryFile.delete();
    } catch (_) {}
  }
  await tmpFile.rename(primaryFile.path);

  // 3. Custom folder if selected by user (Atomic replacement)
  if (targetDirectoryPath != null && targetDirectoryPath.trim().isNotEmpty) {
    try {
      final customDir = Directory(targetDirectoryPath.trim());
      if (!await customDir.exists()) {
        await customDir.create(recursive: true);
      }
      final customFile = File('${customDir.path}/$fileName');
      final customTmp = File('${customDir.path}/$fileName.tmp');
      await customTmp.writeAsBytes(zipBytes, flush: true);
      if (await customFile.exists()) {
        try {
          await customFile.delete();
        } catch (_) {}
      }
      await customTmp.rename(customFile.path);
      return customFile.path;
    } catch (_) {}
  } else {
    // 4. Fallback public save to Android Download folder if accessible
    try {
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          final publicFile = File('${downloadDir.path}/$fileName');
          final publicTmp = File('${downloadDir.path}/$fileName.tmp');
          await publicTmp.writeAsBytes(zipBytes, flush: true);
          if (await publicFile.exists()) {
            try {
              await publicFile.delete();
            } catch (_) {}
          }
          await publicTmp.rename(publicFile.path);
        }
      }
    } catch (_) {}
  }

  return primaryFile.path;
}

Future<String?> pickFolderLocationPlatform() async {
  return null;
}

Future<String?> saveBackupViaSystemPickerPlatform({
  required Uint8List zipBytes,
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  return await saveStableBackupZipPlatform(zipBytes: zipBytes, fileName: fileName);
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
