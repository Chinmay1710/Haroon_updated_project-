import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';

String? _cachedPhotosDirPath;
Directory? _cachedAppDocDir;

void resetCachedPathsForTesting() {
  _cachedPhotosDirPath = null;
  _cachedAppDocDir = null;
}

/// IO implementation for mobile/desktop platforms
Future<void> savePhotoToLocal({required String filePath, required Uint8List bytes}) async {
  String targetPath = filePath;
  // If filePath is relative (e.g. photos/xyz.jpg), make it absolute under localPhotosDir
  if (!filePath.startsWith('/') && !filePath.contains(':\\') && !filePath.startsWith('\\')) {
    final photosDir = await getLocalPhotosDirectory();
    targetPath = '$photosDir/$filePath';
  }
  final file = File(targetPath);
  final parentDir = file.parent;
  if (!await parentDir.exists()) {
    await parentDir.create(recursive: true);
  }
  await file.writeAsBytes(bytes);
}

Future<void> createLocalDirectory({required String dirPath}) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}

Future<Directory> _getAppDocDir() async {
  if (_cachedAppDocDir != null && await _cachedAppDocDir!.exists()) {
    return _cachedAppDocDir!;
  }
  final dir = await getApplicationDocumentsDirectory();
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _cachedAppDocDir = dir;
  return dir;
}

Future<String> getLocalPhotosDirectory() async {
  if (_cachedPhotosDirPath != null && await Directory(_cachedPhotosDirPath!).exists()) {
    return _cachedPhotosDirPath!;
  }
  final appDir = await _getAppDocDir();
  final photosDir = Directory('${appDir.path}/haroon_tailor_photos');
  if (!await photosDir.exists()) {
    await photosDir.create(recursive: true);
  }
  _cachedPhotosDirPath = photosDir.path;
  return _cachedPhotosDirPath!;
}

Future<Uint8List?> readLocalPhotoFile(String filePath) async {
  try {
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    // Also check if relative to local photos directory
    final photosDir = await getLocalPhotosDirectory();
    final cleanRel = filePath.replaceFirst(RegExp(r'^/+'), '');
    final relFile = File('$photosDir/$cleanRel');
    if (await relFile.exists()) {
      return await relFile.readAsBytes();
    }
  } catch (_) {}
  return null;
}

/// Permanent file-based JSON storage on device filesystem
Future<void> saveJsonToFile(String fileName, String content) async {
  try {
    final appDir = await _getAppDocDir();
    final file = File('${appDir.path}/$fileName');
    await file.writeAsString(content, flush: true);
  } catch (e) {
    debugPrint('Error saving $fileName: $e');
  }
}

Future<String?> readJsonFromFile(String fileName) async {
  try {
    final appDir = await _getAppDocDir();
    final file = File('${appDir.path}/$fileName');
    if (await file.exists()) {
      return await file.readAsString();
    }
  } catch (e) {
    debugPrint('Error reading $fileName: $e');
  }
  return null;
}

Future<void> clearAllDiskFiles() async {
  try {
    final appDir = await _getAppDocDir();
    if (await appDir.exists()) {
      final entities = appDir.listSync();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    }
  } catch (_) {}
}

Widget _defaultErrorWidget(double? width, double? height) {
  return Container(
    width: width,
    height: height,
    color: Colors.grey.shade200,
    child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
  );
}

/// Smart image builder that supports:
/// 1. Base64 data URLs (data:image/...)
/// 2. Local device file paths (/path/to/photos/...)
/// 3. Remote HTTP/HTTPS URLs
/// 4. Relative server paths
Widget buildSmartImage(
  String pathOrUrl, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget? errorWidget,
}) {
  final clean = pathOrUrl.trim();
  if (clean.isEmpty || clean == 'null' || clean == 'undefined' || clean == '[]' || clean == 'data:image/jpeg;base64' || clean == 'data:image/png;base64' || clean == 'base64') {
    return errorWidget ?? _defaultErrorWidget(width, height);
  }

  // 1. Base64 data URL or raw base64 string
  if (clean.startsWith('data:image') || clean.startsWith('/9j/') || clean.startsWith('iVBORw0KGgo') || (!clean.startsWith('http') && !clean.contains('/') && clean.length > 50)) {
    try {
      final b64 = clean.contains(',') ? clean.split(',').last : clean;
      return Image.memory(
        base64Decode(b64.replaceAll(RegExp(r'\s+'), '')),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => errorWidget ?? _defaultErrorWidget(width, height),
      );
    } catch (_) {
      return errorWidget ?? _defaultErrorWidget(width, height);
    }
  }

  // 2. Local File path
  if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
    try {
      final file = File(clean);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => errorWidget ?? _defaultErrorWidget(width, height),
        );
      }
      if (clean.startsWith('photos/')) {
        if (_cachedPhotosDirPath != null) {
          final relFile = File('$_cachedPhotosDirPath/$clean');
          if (relFile.existsSync()) {
            return Image.file(
              relFile,
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (context, error, stackTrace) => errorWidget ?? _defaultErrorWidget(width, height),
            );
          }
        }
        return FutureBuilder<String>(
          future: getLocalPhotosDirectory(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final relFile = File('${snapshot.data}/$clean');
              if (relFile.existsSync()) {
                return Image.file(
                  relFile,
                  width: width,
                  height: height,
                  fit: fit,
                  errorBuilder: (context, error, stackTrace) => errorWidget ?? _defaultErrorWidget(width, height),
                );
              }
            }
            return errorWidget ?? _defaultErrorWidget(width, height);
          },
        );
      }
    } catch (_) {}
  }

  // 3. Network URL or relative path
  final fullUrl = clean.startsWith('http')
      ? clean
      : '${ApiService.baseUrl}/${clean.replaceAll('../', '')}';

  return Image.network(
    fullUrl,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => errorWidget ?? _defaultErrorWidget(width, height),
  );
}
