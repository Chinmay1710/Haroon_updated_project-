import 'dart:typed_data';

Future<String?> saveFileToDevice({required String content, required String fileName}) async {
  throw UnsupportedError('Platform not supported for direct file download.');
}

Future<String?> saveZipFileToDevice({required Uint8List zipBytes, required String fileName}) async {
  throw UnsupportedError('Platform not supported for direct ZIP file download.');
}

Future<Uint8List?> pickZipFileFromDevice() async {
  throw UnsupportedError('Platform not supported for file picking.');
}

Future<String?> pickJsonFileFromDevice() async {
  throw UnsupportedError('Platform not supported for file picking.');
}

Future<String?> pickFolderLocationPlatform() async {
  throw UnsupportedError('Platform not supported for folder picking.');
}

Future<String?> saveBackupViaSystemPickerPlatform({
  required Uint8List zipBytes,
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  throw UnsupportedError('Platform not supported for system picker.');
}

Future<String?> saveStableBackupZipPlatform({
  required Uint8List zipBytes,
  String fileName = 'HaroonTailor_Backup.zip',
  String? targetDirectoryPath,
}) async {
  throw UnsupportedError('Platform not supported for stable backup.');
}

Future<Uint8List?> getExistingBackupZipPlatform({
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  throw UnsupportedError('Platform not supported for existing backup.');
}

Future<Map<String, dynamic>> getLastBackupInfoPlatform({
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  throw UnsupportedError('Platform not supported for backup info.');
}
