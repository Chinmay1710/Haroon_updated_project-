import 'dart:typed_data';

void saveFileToDevice({required String content, required String fileName}) {
  throw UnsupportedError('Platform not supported for direct file download.');
}

void saveZipFileToDevice({required Uint8List zipBytes, required String fileName}) {
  throw UnsupportedError('Platform not supported for direct ZIP file download.');
}

Future<Uint8List?> pickZipFileFromDevice() async {
  throw UnsupportedError('Platform not supported for file picking.');
}

Future<String?> pickJsonFileFromDevice() async {
  throw UnsupportedError('Platform not supported for file picking.');
}
