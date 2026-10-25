// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;
import 'package:archive/archive.dart';
import 'io_helper_web.dart';

Future<String?> saveFileToDevice({required String content, required String fileName}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return fileName;
}

Future<String?> saveZipFileToDevice({required Uint8List zipBytes, required String fileName}) async {
  final blob = html.Blob([zipBytes], 'application/zip');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  return fileName;
}

Future<Uint8List?> pickZipFileFromDevice() async {
  final completer = Completer<Uint8List?>();
  final uploadInput = html.FileUploadInputElement()
    ..accept = '.zip,application/zip,application/x-zip-compressed';
  uploadInput.click();

  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final file = files[0];
      final reader = html.FileReader();
      reader.onLoadEnd.listen((e) {
        final res = reader.result;
        if (res != null) {
          if (res is Uint8List) {
            completer.complete(res);
          } else if (res is ByteBuffer) {
            completer.complete(res.asUint8List());
          } else if (res is List<int>) {
            completer.complete(Uint8List.fromList(res));
          } else {
            completer.complete(null);
          }
        } else {
          completer.complete(null);
        }
      });
      reader.onError.listen((e) {
        completer.complete(null);
      });
      reader.readAsArrayBuffer(file);
    } else {
      completer.complete(null);
    }
  });

  return completer.future;
}

Future<String?> pickJsonFileFromDevice() async {
  final completer = Completer<String?>();
  final uploadInput = html.FileUploadInputElement()..accept = '.json,application/json';
  uploadInput.click();

  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final file = files[0];
      final reader = html.FileReader();
      reader.onLoadEnd.listen((e) {
        completer.complete(reader.result as String?);
      });
      reader.onError.listen((e) {
        completer.complete(null);
      });
      reader.readAsText(file);
    } else {
      completer.complete(null);
    }
  });

  return completer.future;
}

Future<String?> saveStableBackupZipPlatform({
  required Uint8List zipBytes,
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  // 1. Validate archive integrity
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
  final hasBackupJson = archive.files.any((f) => f.name == 'backup.json');
  if (!hasBackupJson) {
    throw Exception('Backup validation failed: backup.json is missing in archive');
  }

  // 2. Cache in WebPhotoStorage for instant incremental reuse
  await WebPhotoStorage.savePhoto(fileName, zipBytes);
  try {
    html.window.localStorage['ht_last_backup_time'] = DateTime.now().toIso8601String();
    html.window.localStorage['ht_last_backup_size'] = zipBytes.length.toString();
  } catch (_) {}

  // 3. Trigger download of the single stable file
  final blob = html.Blob([zipBytes], 'application/zip');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);

  return fileName;
}

Future<Uint8List?> getExistingBackupZipPlatform({
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  return await WebPhotoStorage.getPhoto(fileName);
}

Future<Map<String, dynamic>> getLastBackupInfoPlatform({
  String fileName = 'HaroonTailor_Backup.zip',
}) async {
  try {
    final timeStr = html.window.localStorage['ht_last_backup_time'];
    final sizeStr = html.window.localStorage['ht_last_backup_size'];
    if (timeStr != null && timeStr.isNotEmpty) {
      return {
        'exists': true,
        'path': fileName,
        'lastModified': DateTime.tryParse(timeStr),
        'sizeBytes': int.tryParse(sizeStr ?? '0') ?? 0,
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
