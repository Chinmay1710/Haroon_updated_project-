import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

/// Get the permanent, safe file path of the master backup ZIP on device storage
Future<String?> getStableBackupZipPath({String fileName = 'HaroonTailor_Backup.zip'}) async {
  try {
    Directory? dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {}
    try {
      dir ??= await getDownloadsDirectory();
    } catch (_) {}
    dir ??= Directory.current;
    return '${dir.path}/$fileName';
  } catch (_) {
    return null;
  }
}

/// Checks if a photo file exists on disk
Future<bool> isPhotoOnDisk(String targetPhotosDir, String canonicalZipPath) async {
  final cleanRel = canonicalZipPath.replaceFirst(RegExp(r'^/+'), '');
  final f = File('$targetPhotosDir/$cleanRel');
  return await f.exists();
}

/// Saves photo bytes directly to disk with directory creation
Future<void> savePhotoBytesToDisk(String targetPhotosDir, String canonicalZipPath, Uint8List bytes) async {
  final cleanRel = canonicalZipPath.replaceFirst(RegExp(r'^/+'), '');
  final f = File('$targetPhotosDir/$cleanRel');
  final parentDir = f.parent;
  if (!await parentDir.exists()) {
    await parentDir.create(recursive: true);
  }
  await f.writeAsBytes(bytes, flush: true);
}

/// Reads file bytes from disk
Future<Uint8List> readFileBytes(String filePath) async {
  return await File(filePath).readAsBytes();
}

/// Gets file size in bytes
Future<int> getFileSize(String filePath) async {
  final f = File(filePath);
  if (await f.exists()) {
    return await f.length();
  }
  return 0;
}

/// Writes bytes to a temporary zip file and returns its path
Future<String> writeTempZipFile(Uint8List bytes) async {
  final tempDir = await Directory.systemTemp.createTemp('ht_temp_zip_');
  final tmpFile = File('${tempDir.path}/temp_backup.zip');
  await tmpFile.writeAsBytes(bytes, flush: true);
  return tmpFile.path;
}

/// Stream-extracts photos from an existing backup ZIP into local photos directory.
/// Uses streaming so it NEVER loads 300MB+ into RAM!
Future<void> syncPhotosFromExistingZip({
  required String existingZipPath,
  required String targetPhotosDir,
  Set<String>? neededCanonicalPaths,
  Function(String status, double progress)? onProgress,
}) async {
  final zipFile = File(existingZipPath);
  if (!await zipFile.exists()) return;

  // Check if any needed photo is actually missing on disk
  if (neededCanonicalPaths != null && neededCanonicalPaths.isNotEmpty) {
    bool hasMissing = false;
    for (final rel in neededCanonicalPaths) {
      final clean = rel.replaceFirst(RegExp(r'^/+'), '');
      final f = File('$targetPhotosDir/$clean');
      if (!await f.exists()) {
        hasMissing = true;
        break;
      }
    }
    // If all needed photos already exist on disk, no need to extract!
    if (!hasMissing) return;
  }

  onProgress?.call('Restoring cached photos to disk storage...', 0.15);
  try {
    final targetDir = Directory(targetPhotosDir);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    // Stream-based extraction: uses minimal RAM, writes directly to flash storage
    await extractFileToDisk(existingZipPath, targetPhotosDir);
  } catch (_) {}
}

/// Creates a ZIP archive directly on disk using streaming I/O.
/// Zero RAM footprint — never loads full ZIP or photo byte arrays into RAM!
Future<String> createStreamedZipOnDisk({
  required String zipDestinationPath,
  required String backupJsonContent,
  required List<MapEntry<String, String>> photoFilesToInclude,
  Function(String status, double progress)? onProgress,
}) async {
  final destFile = File(zipDestinationPath);
  final parentDir = destFile.parent;
  if (!await parentDir.exists()) {
    await parentDir.create(recursive: true);
  }

  final tmpZipPath = '$zipDestinationPath.tmp';
  final tmpZipFile = File(tmpZipPath);
  if (await tmpZipFile.exists()) {
    try {
      await tmpZipFile.delete();
    } catch (_) {}
  }

  Directory? tempJsonDir;
  try {
    final encoder = ZipFileEncoder();
    encoder.create(tmpZipPath);

    // 1. Write backup.json to temporary file and stream it into the archive
    onProgress?.call('Archiving database records & settings...', 0.86);
    tempJsonDir = await Directory.systemTemp.createTemp('ht_backup_json_');
    final jsonFile = File('${tempJsonDir.path}/backup.json');
    await jsonFile.writeAsString(backupJsonContent, flush: true);
    await encoder.addFile(jsonFile, 'backup.json');

    // 2. Stream each photo file from disk into the archive one-by-one
    final totalPhotos = photoFilesToInclude.length;
    int processed = 0;

    for (final entry in photoFilesToInclude) {
      final canonicalZipPath = entry.key;
      final localFilePath = entry.value;
      final photoFile = File(localFilePath);

      if (await photoFile.exists()) {
        await encoder.addFile(photoFile, canonicalZipPath);
      }

      processed++;
      if (processed % 15 == 0 || processed == totalPhotos) {
        final progress = 0.86 + 0.12 * (totalPhotos > 0 ? processed / totalPhotos : 1.0);
        onProgress?.call('Archiving photos ($processed/$totalPhotos)...', progress);
      }
    }

    // 3. Finalize and close ZIP stream
    await encoder.close();

    // 4. Atomic file rename to replace the destination ZIP file
    if (await destFile.exists()) {
      try {
        await destFile.delete();
      } catch (_) {}
    }
    await tmpZipFile.rename(destFile.path);

    onProgress?.call('Backup ready on device storage!', 1.0);
    return destFile.path;
  } finally {
    if (tempJsonDir != null && await tempJsonDir.exists()) {
      try {
        await tempJsonDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Copies file directly to Android Download directory if accessible
Future<void> copyFileToDownloads(String sourcePath, String fileName) async {
  try {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final target = File('${downloadDir.path}/$fileName');
        await sourceFile.copy(target.path);
      }
    }
  } catch (_) {}
}

Future<void> deleteFileIfExists(String filePath) async {
  try {
    final f = File(filePath);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// Extract backup.json directly from a ZIP file on disk without loading entire ZIP into RAM
Future<String?> extractBackupJsonFromZipFile(String zipFilePath, String targetDir) async {
  final zipFile = File(zipFilePath);
  if (!await zipFile.exists()) return null;

  try {
    await extractFileToDisk(zipFilePath, targetDir);
    final jsonFile = File('$targetDir/backup.json');
    if (await jsonFile.exists()) {
      return await jsonFile.readAsString();
    }
  } catch (_) {}
  return null;
}

/// Streams a local file directly over HTTP to Google Drive with zero memory buffering
Future<http.StreamedResponse?> sendDriveUploadStream({
  required String uploadUrl,
  required String method,
  required String token,
  required String filePath,
}) async {
  final file = File(filePath);
  if (!await file.exists()) return null;

  final req = http.StreamedRequest(method, Uri.parse(uploadUrl));
  req.headers['Authorization'] = 'Bearer $token';
  req.headers['Content-Type'] = 'application/zip';
  req.contentLength = await file.length();
  file.openRead().listen(req.sink.add, onDone: req.sink.close, onError: req.sink.addError);
  return await req.send();
}
