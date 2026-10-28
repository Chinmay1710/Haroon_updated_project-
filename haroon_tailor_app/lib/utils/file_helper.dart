import 'dart:typed_data';
import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';

class FileHelper {
  /// Trigger 1-click download/save of backup JSON file to user's computer/phone
  static Future<String?> downloadBackupJson({
    required String jsonContent,
    String? fileName,
  }) async {
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final name = fileName ?? 'HaroonTailor_Master_Backup_$dateStr.json';
    return await saveFileToDevice(content: jsonContent, fileName: name);
  }

  /// Trigger 1-click download/save of backup ZIP file (with photos)
  static Future<String?> downloadBackupZip({
    required Uint8List zipBytes,
    String? fileName,
  }) async {
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final name = fileName ?? 'HaroonTailor_Backup_$dateStr.zip';
    return await saveZipFileToDevice(zipBytes: zipBytes, fileName: name);
  }

  /// Atomically save or replace the single stable backup ZIP archive ('HaroonTailor_Backup.zip').
  /// Never creates duplicate files and safely preserves the previous backup if errors occur.
  static Future<String?> saveStableBackupZip({
    required Uint8List zipBytes,
    String fileName = 'HaroonTailor_Backup.zip',
    String? targetDirectoryPath,
  }) async {
    return await saveStableBackupZipPlatform(
      zipBytes: zipBytes,
      fileName: fileName,
      targetDirectoryPath: targetDirectoryPath,
    );
  }

  /// Let user choose a folder/location to save backups
  static Future<String?> pickFolderLocation() async {
    return await pickFolderLocationPlatform();
  }

  /// Let user choose location via native system file picker
  static Future<String?> saveBackupViaSystemPicker({
    required Uint8List zipBytes,
    String fileName = 'HaroonTailor_Backup.zip',
  }) async {
    return await saveBackupViaSystemPickerPlatform(
      zipBytes: zipBytes,
      fileName: fileName,
    );
  }

  /// Retrieve raw bytes of the current stable backup ZIP to reuse unchanged photos incrementally
  static Future<Uint8List?> getExistingBackupZip({
    String fileName = 'HaroonTailor_Backup.zip',
  }) async {
    return await getExistingBackupZipPlatform(fileName: fileName);
  }

  /// Check information (exists, last modified, file size) of the stable backup ZIP
  static Future<Map<String, dynamic>> getLastBackupInfo({
    String fileName = 'HaroonTailor_Backup.zip',
  }) async {
    return await getLastBackupInfoPlatform(fileName: fileName);
  }

  /// Open native file picker dialog to let user select their backup JSON file
  static Future<String?> pickBackupJsonFile() async {
    return await pickJsonFileFromDevice();
  }

  /// Open native file picker dialog to let user select their backup ZIP file
  static Future<Uint8List?> pickBackupZipFile() async {
    return await pickZipFileFromDevice();
  }
}
