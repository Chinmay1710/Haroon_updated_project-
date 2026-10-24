import 'dart:typed_data';
import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';

class FileHelper {
  /// Trigger 1-click download/save of backup JSON file to user's computer/phone
  static Future<void> downloadBackupJson({
    required String jsonContent,
    String? fileName,
  }) async {
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final name = fileName ?? 'HaroonTailor_Master_Backup_$dateStr.json';
    saveFileToDevice(content: jsonContent, fileName: name);
  }

  /// Trigger 1-click download/save of backup ZIP file (with photos)
  static Future<void> downloadBackupZip({
    required Uint8List zipBytes,
    String? fileName,
  }) async {
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final name = fileName ?? 'HaroonTailor_Backup_$dateStr.zip';
    saveZipFileToDevice(zipBytes: zipBytes, fileName: name);
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
