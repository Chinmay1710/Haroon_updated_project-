import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';

Future<String> createStreamedZipOnDisk({
  required String zipDestinationPath,
  required String backupJsonContent,
  required List<MapEntry<String, String>> photoFilesToInclude,
  Function(String status, double progress)? onProgress,
}) async {
  return 'HaroonTailor_Backup.zip';
}

Future<void> syncPhotosFromExistingZip({
  required String existingZipPath,
  required String targetPhotosDir,
  Set<String>? neededCanonicalPaths,
  Function(String status, double progress)? onProgress,
}) async {
  // No-op on web
}

Future<String?> getStableBackupZipPath() async {
  return null;
}

Future<bool> isPhotoOnDisk(String targetPhotosDir, String canonicalZipPath) async {
  return false;
}

Future<void> savePhotoBytesToDisk(String targetPhotosDir, String canonicalZipPath, Uint8List bytes) async {
  // No-op on web
}

Future<Uint8List> readFileBytes(String filePath) async {
  return Uint8List(0);
}

Future<int> getFileSize(String filePath) async {
  return 0;
}

Future<String> writeTempZipFile(Uint8List bytes) async {
  return 'temp.zip';
}

Future<void> copyFileToDownloads(String sourcePath, String fileName) async {
  // No-op on web
}

Future<void> deleteFileIfExists(String filePath) async {}

Future<String?> extractBackupJsonFromZipFile(String zipFilePath, String targetDir) async {
  return null;
}

Future<http.StreamedResponse?> sendDriveUploadStream({
  required String uploadUrl,
  required String method,
  required String token,
  required String filePath,
}) async {
  return null;
}
