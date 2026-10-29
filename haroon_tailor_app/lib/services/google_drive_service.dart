import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for Google Drive OAuth 2.0 and Cloud Auto-Backup/Sync.
/// Uses the official Google Drive API v3 with the narrowest scope:
/// `https://www.googleapis.com/auth/drive.file` (only accesses files created by this app).
class GoogleDriveService {
  static const String driveScope = 'https://www.googleapis.com/auth/drive.file';
  static const String backupFileName = 'HaroonTailor_Backup.zip';

  // Preference keys
  static const String _keyClientId = 'ht_gdrive_client_id';
  static const String _keyClientSecret = 'ht_gdrive_client_secret';
  static const String _keyRedirectUri = 'ht_gdrive_redirect_uri';
  static const String _keyAccessToken = 'ht_gdrive_access_token';
  static const String _keyRefreshToken = 'ht_gdrive_refresh_token';
  static const String _keyTokenExpiry = 'ht_gdrive_token_expiry';
  static const String _keyUserEmail = 'ht_gdrive_user_email';
  static const String _keyDriveFileId = 'ht_gdrive_backup_file_id';
  static const String _keyLastCloudSync = 'ht_gdrive_last_cloud_sync';
  static const String _keyLastCloudSyncStatus = 'ht_gdrive_last_cloud_sync_status';
  static const String _keyAutoSyncEnabled = 'ht_gdrive_auto_sync_enabled';

  // In-memory state and synchronization lock
  static bool _isSyncing = false;
  static Timer? _debounceTimer;
  static bool _isDebouncing = false;

  /// Check whether Google Drive synchronization is currently running
  static bool get isSyncing => _isSyncing;
  static bool get isDebouncing => _isDebouncing;

  // ──────────────────────────────────────────────────────────────────────────
  // CONFIGURATION & CREDENTIAL MANAGEMENT (No hardcoded secrets!)
  // ──────────────────────────────────────────────────────────────────────────

  static Future<String?> getClientId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyClientId);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setClientId(String clientId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyClientId, clientId.trim());
    } catch (_) {}
  }

  static Future<String?> getClientSecret() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyClientSecret);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setClientSecret(String secret) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (secret.trim().isEmpty) {
        await prefs.remove(_keyClientSecret);
      } else {
        await prefs.setString(_keyClientSecret, secret.trim());
      }
    } catch (_) {}
  }

  static Future<String?> getRedirectUri() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyRedirectUri);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setRedirectUri(String redirectUri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (redirectUri.trim().isEmpty) {
        await prefs.remove(_keyRedirectUri);
      } else {
        await prefs.setString(_keyRedirectUri, redirectUri.trim());
      }
    } catch (_) {}
  }

  static Future<bool> isConnected() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString(_keyRefreshToken);
      final accessToken = prefs.getString(_keyAccessToken);
      return (refreshToken != null && refreshToken.isNotEmpty) ||
          (accessToken != null && accessToken.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getUserEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyUserEmail);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getLastCloudSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastCloudSync);
    } catch (_) {
      return null;
    }
  }

  static Future<String> getCloudSyncStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastCloudSyncStatus) ?? 'Idle';
    } catch (_) {
      return 'Idle';
    }
  }

  static Future<bool> isAutoSyncEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAutoSyncEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setAutoSyncEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoSyncEnabled, enabled);
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────────
  // OAUTH 2.0 FLOW & TOKEN MANAGEMENT
  // ──────────────────────────────────────────────────────────────────────────

  static String getDefaultRedirectUri() {
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty && origin != 'null') return origin;
      } catch (_) {}
    }
    return 'http://localhost:8085';
  }

  /// Generates the Google OAuth 2.0 Authorization URL for user login.
  static String getAuthorizationUrl({
    required String clientId,
    String? redirectUri,
  }) {
    final effectiveRedirect = redirectUri ?? getDefaultRedirectUri();
    final params = {
      'client_id': clientId,
      'redirect_uri': effectiveRedirect,
      'response_type': 'code',
      'scope': '$driveScope email profile',
      'access_type': 'offline',
      'prompt': 'consent',
    };
    final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', params);
    return uri.toString();
  }

  /// Launch Google OAuth login in browser
  static Future<bool> launchAuthInBrowser({
    required String clientId,
    String? redirectUri,
  }) async {
    final url = getAuthorizationUrl(clientId: clientId, redirectUri: redirectUri);
    final uri = Uri.parse(url);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Extracts an authorization code from either a pasted code or redirect URL.
  static String? extractAuthorizationCode(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri != null && (uri.hasScheme || value.contains('code='))) {
      final code = uri.queryParameters['code']?.trim();
      return code == null || code.isEmpty ? null : code;
    }
    return value;
  }

  /// Exchanges an authorization code for access and refresh tokens
  static Future<Map<String, dynamic>> exchangeAuthCode({
    required String authCode,
    String? clientId,
    String? clientSecret,
    String? redirectUri,
  }) async {
    final resolvedClientId = clientId ?? await getClientId();
    if (resolvedClientId == null || resolvedClientId.isEmpty) {
      return {'success': false, 'error': 'Google Client ID is missing. Please set it in Settings.'};
    }
    final resolvedSecret = clientSecret ?? await getClientSecret() ?? '';
    final effectiveRedirect = redirectUri ?? getDefaultRedirectUri();

    try {
      final body = {
        'code': authCode.trim(),
        'client_id': resolvedClientId,
        'grant_type': 'authorization_code',
        'redirect_uri': effectiveRedirect,
      };
      if (resolvedSecret.isNotEmpty) {
        body['client_secret'] = resolvedSecret;
      }

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final accessToken = data['access_token'] as String?;
        final refreshToken = data['refresh_token'] as String?;
        final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

        if (accessToken != null && accessToken.isNotEmpty) {
          await _saveTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresInSeconds: expiresIn,
          );

          // Fetch user profile email
          String? email;
          try {
            final userInfoRes = await http.get(
              Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
              headers: {'Authorization': 'Bearer $accessToken'},
            );
            if (userInfoRes.statusCode == 200) {
              final userInfo = jsonDecode(userInfoRes.body) as Map<String, dynamic>;
              email = userInfo['email']?.toString();
              if (email != null) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_keyUserEmail, email);
              }
            }
          } catch (_) {}

          return {
            'success': true,
            'email': email ?? 'Connected Google Account',
            'has_refresh_token': refreshToken != null,
          };
        }
      }

      final errBody = response.body;
      return {'success': false, 'error': 'OAuth Token error (${response.statusCode}): $errBody'};
    } catch (e) {
      return {'success': false, 'error': 'Connection failed: $e'};
    }
  }

  /// Directly saves manual tokens (e.g. from developer setup or test environment)
  static Future<void> saveManualTokens({
    required String accessToken,
    String? refreshToken,
    int expiresInSeconds = 3600,
    String? email,
  }) async {
    await _saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresInSeconds: expiresInSeconds,
    );
    if (email != null && email.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserEmail, email);
    }
  }

  static Future<void> _saveTokens({
    required String accessToken,
    String? refreshToken,
    required int expiresInSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString(_keyRefreshToken, refreshToken);
    }
    final expiryTime = DateTime.now().add(Duration(seconds: expiresInSeconds - 60));
    await prefs.setString(_keyTokenExpiry, expiryTime.toIso8601String());
  }

  /// Disconnects Google Drive account and revokes access
  static Future<void> disconnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_keyAccessToken);
      if (accessToken != null && accessToken.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('https://oauth2.googleapis.com/revoke?token=$accessToken'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          );
        } catch (_) {}
      }
      await prefs.remove(_keyAccessToken);
      await prefs.remove(_keyRefreshToken);
      await prefs.remove(_keyTokenExpiry);
      await prefs.remove(_keyUserEmail);
      await prefs.remove(_keyDriveFileId);
      await prefs.remove(_keyLastCloudSync);
      await prefs.setString(_keyLastCloudSyncStatus, 'Disconnected');
    } catch (_) {}
  }

  /// Returns a valid access token, auto-refreshing it if expired.
  static Future<String?> getValidAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_keyAccessToken);
    final expiryStr = prefs.getString(_keyTokenExpiry);
    final refreshToken = prefs.getString(_keyRefreshToken);

    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    // Check expiry
    DateTime? expiry;
    if (expiryStr != null) {
      expiry = DateTime.tryParse(expiryStr);
    }

    final isExpired = expiry != null && DateTime.now().isAfter(expiry);

    if (!isExpired) {
      return accessToken;
    }

    // Attempt token refresh
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final clientId = await getClientId();
    final clientSecret = await getClientSecret() ?? '';
    if (clientId == null || clientId.isEmpty) {
      return null;
    }

    try {
      final body = {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      };
      if (clientSecret.isNotEmpty) {
        body['client_secret'] = clientSecret;
      }

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = data['access_token'] as String?;
        final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          await _saveTokens(
            accessToken: newAccessToken,
            refreshToken: data['refresh_token'] as String? ?? refreshToken,
            expiresInSeconds: expiresIn,
          );
          return newAccessToken;
        }
      } else if (response.statusCode == 400 || response.statusCode == 401) {
        // Token revoked by user
        await prefs.setString(_keyLastCloudSyncStatus, 'Authorization revoked by user');
      }
    } catch (e) {
      debugPrint('Error refreshing Google Drive token: $e');
    }

    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GOOGLE DRIVE API OPERATIONS (Search, Upload, Download)
  // ──────────────────────────────────────────────────────────────────────────

  /// Finds existing backup file in Google Drive
  static Future<Map<String, dynamic>?> findBackupFile() async {
    final token = await getValidAccessToken();
    if (token == null) return null;

    try {
      final query = "name = '$backupFileName' and trashed = false";
      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent(query)}&fields=files(id,name,size,modifiedTime,md5Checksum,webViewLink)',
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List<dynamic>?;
        if (files != null && files.isNotEmpty) {
          final fileInfo = files.first as Map<String, dynamic>;
          // Cache file ID
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyDriveFileId, fileInfo['id'].toString());
          return fileInfo;
        }
      }
    } catch (e) {
      debugPrint('findBackupFile error: $e');
    }
    return null;
  }

  /// Uploads or atomically updates the backup ZIP file in Google Drive
  static Future<Map<String, dynamic>> uploadBackupZip({
    required Uint8List zipBytes,
    Function(String status, double progress)? onProgress,
  }) async {
    if (_isSyncing) {
      return {'success': false, 'error': 'Another sync operation is currently running.'};
    }

    _isSyncing = true;
    final prefs = await SharedPreferences.getInstance();

    try {
      onProgress?.call('Authenticating with Google Drive...', 0.1);
      final token = await getValidAccessToken();
      if (token == null) {
        await prefs.setString(_keyLastCloudSyncStatus, 'Authentication required or token expired');
        return {
          'success': false,
          'error': 'Google Drive account is not connected or token has expired. Please re-connect.',
        };
      }

      onProgress?.call('Checking existing cloud backup on Google Drive...', 0.3);
      final existingFile = await findBackupFile();
      final existingFileId = existingFile?['id'] as String?;

      http.Response response;

      if (existingFileId != null && existingFileId.isNotEmpty) {
        // Atomic update of existing file
        onProgress?.call('Updating HaroonTailor_Backup.zip in Google Drive...', 0.6);
        final updateUri = Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files/$existingFileId?uploadType=media',
        );

        response = await http.patch(
          updateUri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/zip',
          },
          body: zipBytes,
        ).timeout(const Duration(seconds: 60));
      } else {
        // Multipart upload to create new file
        onProgress?.call('Creating HaroonTailor_Backup.zip in Google Drive...', 0.6);
        const boundary = '-------HaroonTailorBoundaryXYZ';
        final metadata = jsonEncode({
          'name': backupFileName,
          'mimeType': 'application/zip',
          'description': 'Automated complete backup of Haroon Tailor shop data and measurements',
        });

        final List<int> body = [];
        body.addAll(utf8.encode('--$boundary\r\n'));
        body.addAll(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'));
        body.addAll(utf8.encode('$metadata\r\n'));
        body.addAll(utf8.encode('--$boundary\r\n'));
        body.addAll(utf8.encode('Content-Type: application/zip\r\n\r\n'));
        body.addAll(zipBytes);
        body.addAll(utf8.encode('\r\n--$boundary--\r\n'));

        final uploadUri = Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
        );

        response = await http.post(
          uploadUri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'multipart/related; boundary=$boundary',
          },
          body: body,
        ).timeout(const Duration(seconds: 60));
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body) as Map<String, dynamic>;
        final fileId = resData['id']?.toString() ?? existingFileId;
        final nowStr = DateTime.now().toIso8601String();

        if (fileId != null) {
          await prefs.setString(_keyDriveFileId, fileId);
        }
        await prefs.setString(_keyLastCloudSync, nowStr);
        await prefs.setString(_keyLastCloudSyncStatus, 'Success ($nowStr)');

        onProgress?.call('✅ Google Drive sync complete!', 1.0);

        return {
          'success': true,
          'file_id': fileId,
          'sync_time': nowStr,
          'size': zipBytes.length,
        };
      } else {
        final err = 'Drive upload failed (${response.statusCode}): ${response.body}';
        await prefs.setString(_keyLastCloudSyncStatus, err);
        return {'success': false, 'error': err};
      }
    } catch (e) {
      final err = 'Drive sync error: $e';
      await prefs.setString(_keyLastCloudSyncStatus, err);
      return {'success': false, 'error': err};
    } finally {
      _isSyncing = false;
    }
  }

  /// Downloads the backup ZIP file from Google Drive
  static Future<Uint8List?> downloadBackupZip({
    Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Connecting to Google Drive...', 0.1);
    final token = await getValidAccessToken();
    if (token == null) {
      throw Exception('Not connected to Google Drive or token expired.');
    }

    onProgress?.call('Locating HaroonTailor_Backup.zip...', 0.25);
    final fileInfo = await findBackupFile();
    if (fileInfo == null || fileInfo['id'] == null) {
      throw Exception('HaroonTailor_Backup.zip was not found in your Google Drive account.');
    }

    final fileId = fileInfo['id'].toString();
    onProgress?.call('Downloading backup from Google Drive...', 0.5);

    final downloadUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final response = await http.get(
      downloadUri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 90));

    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      final bytes = response.bodyBytes;
      // Quick magic bytes check: ZIP files start with PK (0x50, 0x4B)
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
        throw Exception('Downloaded file from Google Drive is not a valid ZIP archive.');
      }
      onProgress?.call('✅ Download complete!', 1.0);
      return bytes;
    } else {
      throw Exception('Failed to download from Drive (${response.statusCode}): ${response.body}');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DEBOUNCED AUTOMATIC BACKUP TRIGGER
  // ──────────────────────────────────────────────────────────────────────────

  /// Call whenever application data (orders, customers, settings, payments) changes.
  /// Debounces rapid successive changes by [delaySeconds] (default 15s) so multiple
  /// updates within a short period trigger only a single efficient background backup.
  static void scheduleAutoSync({
    int delaySeconds = 15,
    required Future<Uint8List> Function() generateBackupZip,
    required Future<String?> Function(Uint8List zipBytes) saveLocalBackup,
  }) {
    _debounceTimer?.cancel();
    _isDebouncing = true;

    _debounceTimer = Timer(Duration(seconds: delaySeconds), () async {
      _isDebouncing = false;
      await performAutoSync(
        generateBackupZip: generateBackupZip,
        saveLocalBackup: saveLocalBackup,
      );
    });
  }

  /// Performs the actual auto-sync operation with retry logic
  static Future<bool> performAutoSync({
    required Future<Uint8List> Function() generateBackupZip,
    required Future<String?> Function(Uint8List zipBytes) saveLocalBackup,
    int maxRetries = 2,
  }) async {
    if (_isSyncing) return false;

    final connected = await isConnected();
    final autoEnabled = await isAutoSyncEnabled();

    if (!connected || !autoEnabled) return false;

    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        // 1. Generate local backup ZIP and validate
        final zipBytes = await generateBackupZip();
        if (zipBytes.isEmpty) return false;

        // 2. Safely save locally first (ensures local data is never lost!)
        final localPath = await saveLocalBackup(zipBytes);
        if (localPath == null || localPath.isEmpty) {
          throw Exception('The backup archive could not be saved to this device.');
        }

        // 3. Upload to Google Drive
        final res = await uploadBackupZip(zipBytes: zipBytes);
        if (res['success'] == true) {
          return true;
        }

        attempt++;
        if (attempt <= maxRetries) {
          // Exponential backoff: 3s, 9s
          await Future.delayed(Duration(seconds: 3 * attempt));
        }
      } catch (e) {
        attempt++;
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(seconds: 3 * attempt));
        } else {
          debugPrint('Auto sync failed after retries: $e');
        }
      }
    }
    return false;
  }
}
