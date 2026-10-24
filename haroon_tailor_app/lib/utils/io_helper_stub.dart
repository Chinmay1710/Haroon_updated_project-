import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Stub implementation for platforms that don't support dart:io
Future<void> savePhotoToLocal({required String filePath, required Uint8List bytes}) async {
  // No-op on unsupported platforms (web)
}

Future<void> createLocalDirectory({required String dirPath}) async {
  // No-op on unsupported platforms (web)
}

Future<String> getLocalPhotosDirectory() async {
  return '';
}

Future<Uint8List?> readLocalPhotoFile(String filePath) async {
  return null;
}

Widget buildSmartImage(
  String pathOrUrl, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget? errorWidget,
}) {
  return errorWidget ??
      Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
      );
}
