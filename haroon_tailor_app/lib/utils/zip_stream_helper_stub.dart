import 'dart:typed_data';
import 'package:http/http.dart' as http;

Future<String> createStreamedZipOnDisk({
  required String zipDestinationPath,
  required String backupJsonContent,
  required List<MapEntry<String, String>> photoFilesToInclude,
  Function(String status, double progress)? onProgress,
}) async {
  throw UnsupportedError('Streaming ZIP to disk is not supported on this platform.');
}

Future<void> syncPhotosFromExistingZip({
  required String existingZipPath,
  required String targetPhotosDir,
  Set<String>? neededCanonicalPaths,
  Function(String status, double progress)? onProgress,
}) async {
  throw UnsupportedError('Streaming ZIP extraction is not supported on this platform.');
}

Future<String?> getStableBackupZipPath() async {
  return null;
}

Future<bool> isPhotoOnDisk(String targetPhotosDir, String canonicalZipPath) async {
  return false;
}

Future<void> savePhotoBytesToDisk(String targetPhotosDir, String canonicalZipPath, Uint8List bytes) async {
  throw UnsupportedError('Saving photo bytes not supported on this platform.');
}

Future<Uint8List> readFileBytes(String filePath) async {
  throw UnsupportedError('File reading not supported on this platform.');
}

Future<int> getFileSize(String filePath) async {
  return 0;
}

Future<String> writeTempZipFile(Uint8List bytes) async {
  throw UnsupportedError('Temp file writing not supported on this platform.');
}

Future<void> copyFileToDownloads(String sourcePath, String fileName) async {
  throw UnsupportedError('Downloads directory copy not supported on this platform.');
}

Future<void> deleteFileIfExists(String filePath) async {}

Future<String?> extractBackupJsonFromZipFile(String zipFilePath, String targetDir) async {
  throw UnsupportedError('Direct file extraction not supported on this platform.');
}

Future<http.StreamedResponse?> sendDriveUploadStream({
  required String uploadUrl,
  required String method,
  required String token,
  required String filePath,
}) async {
  return null;
}
