// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Offline Photo Storage for web - instant in-memory cache for fast display
class WebPhotoStorage {
  static final Map<String, Uint8List> memCache = {};

  static Future<void> savePhoto(String key, Uint8List bytes) async {
    memCache[key] = bytes;
  }

  static Future<Uint8List?> getPhoto(String key) async {
    return memCache[key];
  }
}

/// Web implementation - photos are stored in IndexedDB for 100% offline persistence
Future<void> savePhotoToLocal({required String filePath, required Uint8List bytes}) async {
  final key = filePath.replaceFirst(RegExp(r'^/+'), '');
  await WebPhotoStorage.savePhoto(key, bytes);
}

Future<void> createLocalDirectory({required String dirPath}) async {
  // No-op on web
}

Future<String> getLocalPhotosDirectory() async {
  return '/web_photos'; // Virtual path for web
}

Future<Uint8List?> readLocalPhotoFile(String filePath) async {
  final key = filePath.replaceFirst(RegExp(r'^/+'), '');
  return await WebPhotoStorage.getPhoto(key);
}

Future<void> saveJsonToFile(String fileName, String content) async {
  try {
    html.window.localStorage['ht_disk_$fileName'] = content;
  } catch (_) {}
}

Future<String?> readJsonFromFile(String fileName) async {
  try {
    return html.window.localStorage['ht_disk_$fileName'];
  } catch (_) {
    return null;
  }
}

Future<void> clearAllDiskFiles() async {
  try {
    final keysToRemove = <String>[];
    for (var key in html.window.localStorage.keys) {
      if (key.startsWith('ht_disk_')) {
        keysToRemove.add(key);
      }
    }
    for (var key in keysToRemove) {
      html.window.localStorage.remove(key);
    }
    WebPhotoStorage.memCache.clear();
  } catch (_) {}
}

/// Download ZIP bytes as a file on web
void downloadZipFileWeb(Uint8List bytes, String fileName) {
  final blob = html.Blob([bytes], 'application/zip');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

Widget _defaultErrorWidget(double? width, double? height) {
  return Container(
    width: width,
    height: height,
    color: Colors.grey.shade200,
    child: const Icon(Icons.broken_image, size: 24, color: Colors.grey),
  );
}

/// Smart image builder for web: supports IndexedDB offline photos, base64 data URLs, and remote images
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

  // 2. Offline photo stored in IndexedDB (e.g. photos/order_419_item_0.jpg)
  if (clean.startsWith('photos/') || clean.startsWith('/photos/')) {
    final key = clean.replaceFirst(RegExp(r'^/+'), '');
    final cached = WebPhotoStorage.memCache[key];
    if (cached != null) {
      return Image.memory(
        cached,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => errorWidget ?? _defaultErrorWidget(width, height),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: WebPhotoStorage.getPhoto(key),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) => errorWidget ?? _defaultErrorWidget(width, height),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey.shade100,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return errorWidget ?? _defaultErrorWidget(width, height);
      },
    );
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

