import 'package:file_picker/file_picker.dart';
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

  /// Open native file picker dialog to let user select their backup JSON file
  static Future<String?> pickBackupJsonFile() async {
    final pickedFiles = await FilePicker.pickFiles(
      dialogTitle: 'Select Haroon Tailor Backup JSON File',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (pickedFiles.isEmpty) {
      return null;
    }

    final picked = pickedFiles.first;
    return await picked.xFile.readAsString();
  }
}
