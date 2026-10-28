import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../services/zip_backup_service.dart';
import '../services/google_drive_service.dart';
import '../utils/phone_utils.dart';
import '../utils/file_helper.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  final ValueChanged<ThemeMode>? onThemeChanged;
  const SettingsScreen({super.key, this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // 1. Clothing Types
  List<String> _clothingTypes = [];
  final TextEditingController _newTypeCtrl = TextEditingController();

  // 2. Message Templates
  Map<String, String> _templates = {};
  String _selectedTemplateKey = 'new_order';
  final TextEditingController _templateEditorCtrl = TextEditingController();

  // 3. Backup & Sync
  DateTime? _lastSyncTime;
  int _cachedOrdersCount = 0;
  int _cachedCustomersCount = 0;
  bool _isBackingUp = false;
  bool _isOfflineMode = false;
  String? _lastBackupTimeStr;
  int? _lastBackupSizeBytes;
  String? _lastBackupPath;

  // Google Drive state
  bool _gDriveConnected = false;
  String? _gDriveEmail;
  String? _gDriveLastSyncTime;
  String _gDriveSyncStatus = 'Idle';
  bool _gDriveAutoSync = true;
  bool _isGDriveSyncing = false;


  // 4. Language & Theme
  String _currentTheme = 'light';
  String _currentLanguage = 'en';

  // 5. Shop Profile & Defaults
  final TextEditingController _shopNameCtrl = TextEditingController();
  final TextEditingController _ownerNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  String _measurementUnit = 'Inches (in)';
  int _defaultDeliveryDays = 7;
  Map<String, double> _defaultRates = {};

  Map<String, List<String>> _clothingNotesMap = {};
  String _selectedClothingTypeForNotes = 'Shirt';
  final TextEditingController _newNoteCtrl = TextEditingController();

  final List<String> _suggestionChips = [
    'Sadri / Waistcoat',
    'Blouse',
    'Salwar Kameez',
    'Lehenga',
    'Nehru Jacket',
    'Pathani Suit',
    'Indo-Western',
    'Safari Suit',
    'Coat / Blazer',
    'Kaftan',
    'Bandhgala',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadAllSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _newTypeCtrl.dispose();
    _newNoteCtrl.dispose();
    _templateEditorCtrl.dispose();
    _shopNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    setState(() => _isLoading = true);
    try {
      final types = await LocalStorageService.getGarmentTypes();
      final templates = await LocalStorageService.getMessageTemplates();
      final theme = await LocalStorageService.getAppTheme();
      final lang = await LocalStorageService.getAppLanguage();
      final unit = await LocalStorageService.getMeasurementUnit();
      final days = await LocalStorageService.getDefaultDeliveryDays();
      final rates = await LocalStorageService.getDefaultRates();
      final syncTime = await LocalStorageService.getLastSyncTime();
      final cachedOrders = await LocalStorageService.getCachedOrders();
      final cachedCust = await LocalStorageService.getCachedCustomers();
      final shop = await ApiService.getShopSettings();
      final isOffline = await LocalStorageService.isOfflineMode();
      final clothingNotes = await LocalStorageService.getClothingNotesMap();
      final bInfo = await FileHelper.getLastBackupInfo();
      final bRecord = await LocalStorageService.getLastBackupRecord();
      String? bTime = bRecord['timestamp']?.toString();
      int? bSize = bRecord['sizeBytes'] as int?;
      String? bPath = bRecord['path']?.toString();
      if (bInfo['exists'] == true) {
        bTime ??= (bInfo['lastModified'] as DateTime?)?.toIso8601String();
        bSize ??= bInfo['sizeBytes'] as int?;
        bPath ??= bInfo['path']?.toString();
      }

      final gDriveConnected = await GoogleDriveService.isConnected();
      final gDriveEmail = await GoogleDriveService.getUserEmail();
      final gDriveLastSync = await GoogleDriveService.getLastCloudSyncTime();
      final gDriveSyncStatus = await GoogleDriveService.getCloudSyncStatus();
      final gDriveAutoSync = await GoogleDriveService.isAutoSyncEnabled();

      if (!mounted) return;
      setState(() {
        _clothingTypes = types;
        _templates = templates;
        _templateEditorCtrl.text = templates[_selectedTemplateKey] ?? '';
        _currentTheme = theme;
        _currentLanguage = lang;
        _measurementUnit = unit;
        _defaultDeliveryDays = days;
        _defaultRates = rates;
        _lastSyncTime = syncTime;
        _cachedOrdersCount = cachedOrders?.length ?? 0;
        _cachedCustomersCount = cachedCust?.length ?? 0;
        _isOfflineMode = isOffline;
        _clothingNotesMap = clothingNotes;
        if (types.isNotEmpty && !_clothingNotesMap.containsKey(_selectedClothingTypeForNotes)) {
          _selectedClothingTypeForNotes = types.first;
        }
        _lastBackupTimeStr = bTime;
        _lastBackupSizeBytes = bSize;
        _lastBackupPath = bPath;

        _gDriveConnected = gDriveConnected;
        _gDriveEmail = gDriveEmail;
        _gDriveLastSyncTime = gDriveLastSync;
        _gDriveSyncStatus = gDriveSyncStatus;
        _gDriveAutoSync = gDriveAutoSync;

        _shopNameCtrl.text = shop['shop_name']?.toString() ?? 'Haroon Tailor';
        _ownerNameCtrl.text = shop['owner_name']?.toString() ?? '';
        _phoneCtrl.text = shop['phone']?.toString() ?? '';
        _addressCtrl.text = shop['address']?.toString() ?? '';
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. CLOTHING TYPES ACTIONS
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _addNewClothingType(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;

    final added = await LocalStorageService.addGarmentType(clean);
    if (added) {
      final updated = await LocalStorageService.getGarmentTypes();
      setState(() {
        _clothingTypes = updated;
        _newTypeCtrl.clear();
      });
      // Sync to backend
      ApiService.updateShopSettings({'clothing_types': updated.join(',')}).ignore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$clean" joda gaya!'), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$clean" pehle se maujood hai!'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _removeClothingType(String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Garment Hatayein?'),
        content: Text('Kya aap sachme "$type" ko list se hatana chahte hain?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hatao (Delete)', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LocalStorageService.removeGarmentType(type);
      final updated = await LocalStorageService.getGarmentTypes();
      setState(() => _clothingTypes = updated);
      ApiService.updateShopSettings({'clothing_types': updated.join(',')}).ignore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$type" list se hata diya gaya.'), backgroundColor: Colors.blueGrey),
        );
      }
    }
  }

  Future<void> _editClothingType(String oldName) async {
    final editCtrl = TextEditingController(text: oldName);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Garment ($oldName)'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: editCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Naya Naam',
              hintText: 'Jaise: Full Shirt, Cotton Pant, etc.',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Naam khali nahi ho sakta';
              if (val.toLowerCase() != oldName.toLowerCase() &&
                  _clothingTypes.any((t) => t.toLowerCase() == val.toLowerCase())) {
                return 'Yeh garment pehle se list me hai';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save Karein', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newName = editCtrl.text.trim();
      final success = await LocalStorageService.editGarmentType(oldName: oldName, newName: newName);
      if (success) {
        final updatedTypes = await LocalStorageService.getGarmentTypes();
        final updatedRates = await LocalStorageService.getDefaultRates();
        final updatedNotes = await LocalStorageService.getClothingNotesMap();
        setState(() {
          _clothingTypes = updatedTypes;
          _defaultRates = updatedRates;
          _clothingNotesMap = updatedNotes;
          if (_selectedClothingTypeForNotes == oldName) {
            _selectedClothingTypeForNotes = newName;
          }
        });
        ApiService.updateShopSettings({'clothing_types': updatedTypes.join(',')}).ignore();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$oldName" badal kar "$newName" kar diya gaya!'), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  Future<void> _resetClothingTypes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Default List Reset Karein?'),
        content: const Text('Sabhi standard kapde (Shirt, Pant, Kurta, etc.) wapas aa jayenge.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LocalStorageService.saveGarmentTypes(List.from(LocalStorageService.defaultGarmentTypes));
      final updated = await LocalStorageService.getGarmentTypes();
      setState(() => _clothingTypes = updated);
      ApiService.updateShopSettings({'clothing_types': updated.join(',')}).ignore();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. MESSAGE TEMPLATES ACTIONS
  // ──────────────────────────────────────────────────────────────────────────
  void _selectTemplate(String key) {
    setState(() {
      _selectedTemplateKey = key;
      _templateEditorCtrl.text = _templates[key] ?? '';
    });
  }

  Future<void> _saveCurrentTemplate() async {
    _templates[_selectedTemplateKey] = _templateEditorCtrl.text.trim();
    await LocalStorageService.saveMessageTemplates(_templates);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message template save ho gaya!'), backgroundColor: Colors.green),
      );
    }
  }

  void _insertPlaceholder(String placeholder) {
    final text = _templateEditorCtrl.text;
    final selection = _templateEditorCtrl.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, placeholder);
      _templateEditorCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + placeholder.length),
      );
    } else {
      _templateEditorCtrl.text = '$text$placeholder';
    }
  }

  String _formatPreviewText(String template) {
    return template
        .replaceAll('{customer_name}', 'Rahul Sharma')
        .replaceAll('{order_number}', '1042')
        .replaceAll('{garments}', '2x Kurta, 1x Pajama')
        .replaceAll('{delivery_date}', '28 Oct 2026')
        .replaceAll('{total_amount}', '1,800')
        .replaceAll('{advance_amount}', '500')
        .replaceAll('{balance_amount}', '1,300')
        .replaceAll('{shop_name}', _shopNameCtrl.text.isNotEmpty ? _shopNameCtrl.text : 'Haroon Tailor')
        .replaceAll('{shop_phone}', _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : '9876543210');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. BACKUP & SYNC ACTIONS
  // ──────────────────────────────────────────────────────────────────────────


  Widget _buildRestoreStatRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }



  // ──────────────────────────────────────────────────────────────────────────
  // ZIP BACKUP & RESTORE (WITH PHOTOS)
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _downloadZipBackup() async {
    setState(() => _isBackingUp = true);

    final progressStatusNotifier = ValueNotifier<String>('Starting backup...');
    final progressValueNotifier = ValueNotifier<double>(0.0);

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.archive, color: Color(0xFF7C3AED)),
              SizedBox(width: 10),
              Text('Creating ZIP Backup'),
            ],
          ),
          content: AnimatedBuilder(
            animation: Listenable.merge([progressStatusNotifier, progressValueNotifier]),
            builder: (ctx, _) {
              final val = progressValueNotifier.value;
              final status = progressStatusNotifier.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: val > 0 ? val : null,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    status,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(val * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF7C3AED)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      final zipBytes = await ZipBackupService.createZipBackup(
        onProgress: (status, progress) {
          progressStatusNotifier.value = status;
          progressValueNotifier.value = progress;
        },
      );

      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      // Save/update the single stable backup ZIP file (HaroonTailor_Backup.zip)
      final savedPath = await FileHelper.saveStableBackupZip(zipBytes: zipBytes);
      final finalPath = savedPath ?? 'HaroonTailor_Backup.zip';

      await LocalStorageService.recordBackupSuccess(
        path: finalPath,
        sizeBytes: zipBytes.length,
      );

      await _loadAllSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Single Backup updated! (${_formatFileSize(zipBytes.length)})\nSaved: $finalPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      // Close progress dialog if still open
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ZIP Backup failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  String _formatBackupDate(String? isoStr) {
    if (isoStr == null || isoStr.isEmpty) return 'Never';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year;
      final hour = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$day-$month-$year $hour:$min';
    } catch (_) {
      return isoStr;
    }
  }



  Future<void> _restoreFromZipFile() async {
    try {
      // 1. Choose restore source (Local File or Google Drive)
      final source = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Restore Source',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose where to restore your backup data from:',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.folder_zip, color: Color(0xFF7C3AED)),
                  ),
                  title: const Text('Restore from Local Device ZIP', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Choose a ZIP backup file stored on this device'),
                  onTap: () => Navigator.pop(ctx, 'local'),
                ),
                const Divider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.cloud_download, color: Color(0xFF2563EB)),
                  ),
                  title: const Text('Restore from Google Drive', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _gDriveConnected
                        ? 'Download HaroonTailor_Backup.zip from ${_gDriveEmail ?? "Google Drive"}'
                        : 'Google Drive is not connected yet (connect in settings)',
                    style: TextStyle(
                      color: _gDriveConnected ? const Color(0xFF64748B) : Colors.orange.shade800,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'drive'),
                ),
              ],
            ),
          ),
        ),
      );

      if (source == null) return;

      Uint8List? zipBytes;

      if (source == 'local') {
        zipBytes = await FileHelper.pickBackupZipFile();
        if (zipBytes == null) return; // User cancelled
      } else if (source == 'drive') {
        if (!_gDriveConnected) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please connect your Google Drive account first in settings.')),
            );
          }
          return;
        }

        // Download from Google Drive with progress
        final downloadProgressNotifier = ValueNotifier<String>('Connecting to Google Drive...');
        final downloadValueNotifier = ValueNotifier<double>(0.0);

        if (!mounted) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.cloud_download, color: Color(0xFF2563EB)),
                  SizedBox(width: 10),
                  Text('Downloading Cloud Backup'),
                ],
              ),
              content: AnimatedBuilder(
                animation: Listenable.merge([downloadProgressNotifier, downloadValueNotifier]),
                builder: (ctx, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: downloadValueNotifier.value > 0 ? downloadValueNotifier.value : null,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        downloadProgressNotifier.value,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        try {
          zipBytes = await GoogleDriveService.downloadBackupZip(
            onProgress: (status, progress) {
              downloadProgressNotifier.value = status;
              downloadValueNotifier.value = progress;
            },
          );
        } catch (e) {
          if (mounted) {
            Navigator.of(context).pop(); // Close download dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red),
            );
          }
          return;
        }

        if (mounted) Navigator.of(context).pop(); // Close download dialog
        if (zipBytes == null) return;
      }

      // 2. Validate & Conflict Check
      final meta = await ZipBackupService.peekBackupMetadata(zipBytes!);
      if (meta != null && meta['timestamp'] != null) {
        final backupTs = meta['timestamp'].toString();
        final isLocalNewer = await LocalStorageService.isLocalDataNewerThan(backupTs);
        if (isLocalNewer && mounted) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text('Newer Local Data Found'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Aapke phone me backup se naya data maujood hai.'),
                  const SizedBox(height: 8),
                  Text('Backup Time: ${_formatBackupDate(backupTs)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  const Text('Agar aap restore karenge to naye orders ya changes backup wale data se replace ho jayenge. Kya aap aage badhna chahte hain?'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel (Data Safe Rakhein)'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Overwrite & Restore'),
                ),
              ],
            ),
          );

          if (proceed != true) return;
        }
      }

      if (!mounted) return;
      setState(() => _isBackingUp = true);

      final progressStatusNotifier = ValueNotifier<String>('Opening ZIP file...');
      final progressValueNotifier = ValueNotifier<double>(0.0);

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.unarchive, color: Color(0xFF16A34A)),
                SizedBox(width: 10),
                Text('Restoring Backup'),
              ],
            ),
            content: AnimatedBuilder(
              animation: Listenable.merge([progressStatusNotifier, progressValueNotifier]),
              builder: (ctx, _) {
                final val = progressValueNotifier.value;
                final status = progressStatusNotifier.value;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: val > 0 ? val : null,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF16A34A)),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      status,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(val * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF16A34A)),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      final res = await ZipBackupService.restoreFromZip(
        zipBytes: zipBytes,
        onProgress: (status, progress) {
          progressStatusNotifier.value = status;
          progressValueNotifier.value = progress;
        },
      );

      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      await _loadAllSettings();
      if (mounted) setState(() => _isBackingUp = false);

      if (!mounted) return;

      if (res['success'] == true) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text('Backup Restored!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aapki backup se poora data, photos aur order statuses restore ho gaye:'),
                const SizedBox(height: 14),
                _buildRestoreStatRow(Icons.receipt_long, '${res['orders_count']} Orders restored'),
                _buildRestoreStatRow(Icons.people, '${res['customers_count']} Customers restored'),
                _buildRestoreStatRow(Icons.photo_library, '${res['photos_saved_locally']} Photos saved locally'),
                _buildRestoreStatRow(Icons.straighten, '${res['measurements_count']} Naap measurements'),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.offline_bolt, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Photos + Data sab 100% offline & fast! Safe copy verified.',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF166534), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  HaroonTailorApp.restartApp(context);
                },
                child: const Text('Dashboard Dekhein'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore error: ${res['error'] ?? "Invalid backup file"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        try { Navigator.of(context).pop(); } catch (_) {}
        setState(() => _isBackingUp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GOOGLE DRIVE CONNECTION & SYNC HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _connectGoogleDriveDialog() async {
    final existingClientId = await GoogleDriveService.getClientId() ?? '';
    final clientIdCtrl = TextEditingController(text: existingClientId);
    final secretCtrl = TextEditingController(text: await GoogleDriveService.getClientSecret() ?? '');
    final codeCtrl = TextEditingController();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.cloud_sync, color: Color(0xFF2563EB)),
              SizedBox(width: 10),
              Text('Connect Google Drive', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Apne Google Drive account ko connect karein taaki aapka data hamesha surakshit rahe.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: clientIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Google OAuth Client ID',
                    hintText: 'xxxxxx.apps.googleusercontent.com',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: secretCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Client Secret (Optional)',
                    hintText: 'Leave empty for Desktop/Mobile Client',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 18),
                  label: const Text('1. Sign In With Google'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(40),
                  ),
                  onPressed: () async {
                    final cid = clientIdCtrl.text.trim();
                    if (cid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a Google Client ID first.')),
                      );
                      return;
                    }
                    await GoogleDriveService.setClientId(cid);
                    await GoogleDriveService.setClientSecret(secretCtrl.text.trim());
                    await GoogleDriveService.launchAuthInBrowser(clientId: cid);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: '2. Paste Authorization Code / Token',
                    hintText: 'Paste code received after Google Sign-in',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final code = codeCtrl.text.trim();
                final cid = clientIdCtrl.text.trim();
                if (code.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter authorization code.')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                setState(() => _isGDriveSyncing = true);

                // If code is an OAuth authorization code or bearer token:
                Map<String, dynamic> res;
                if (code.startsWith('ya29.')) {
                  // Direct token
                  await GoogleDriveService.saveManualTokens(accessToken: code, email: 'Connected Google Account');
                  res = {'success': true, 'email': 'Connected Google Account'};
                } else {
                  res = await GoogleDriveService.exchangeAuthCode(
                    authCode: code,
                    clientId: cid.isNotEmpty ? cid : null,
                    clientSecret: secretCtrl.text.trim().isNotEmpty ? secretCtrl.text.trim() : null,
                  );
                }

                await _loadAllSettings();
                setState(() => _isGDriveSyncing = false);

                if (mounted) {
                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✅ Connected to Google Drive! (${res['email'] ?? ""})'), backgroundColor: Colors.green),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Connection failed: ${res['error']}'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Verify & Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _disconnectGoogleDrive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google Drive?'),
        content: const Text('Are you sure you want to disconnect Google Drive? Automatic cloud backup will be stopped.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await GoogleDriveService.disconnect();
      await _loadAllSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Drive disconnected.')),
        );
      }
    }
  }

  Future<void> _syncToGoogleDriveNow() async {
    if (_isGDriveSyncing || _isBackingUp) return;

    setState(() => _isGDriveSyncing = true);
    final progressStatusNotifier = ValueNotifier<String>('Starting Drive sync...');
    final progressValueNotifier = ValueNotifier<double>(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.cloud_upload, color: Color(0xFF2563EB)),
              SizedBox(width: 10),
              Text('Syncing to Google Drive'),
            ],
          ),
          content: AnimatedBuilder(
            animation: Listenable.merge([progressStatusNotifier, progressValueNotifier]),
            builder: (ctx, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progressValueNotifier.value > 0 ? progressValueNotifier.value : null,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    progressStatusNotifier.value,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      // 1. Generate local backup ZIP
      progressStatusNotifier.value = 'Preparing local backup archive...';
      progressValueNotifier.value = 0.2;
      final zipBytes = await ZipBackupService.createZipBackup(
        onProgress: (status, p) {
          progressStatusNotifier.value = status;
          progressValueNotifier.value = 0.2 + (p * 0.4);
        },
      );

      // 2. Save locally first
      final savedPath = await FileHelper.saveStableBackupZip(zipBytes: zipBytes);
      await LocalStorageService.recordBackupSuccess(
        path: savedPath ?? 'HaroonTailor_Backup.zip',
        sizeBytes: zipBytes.length,
      );

      // 3. Upload to Google Drive
      final uploadRes = await GoogleDriveService.uploadBackupZip(
        zipBytes: zipBytes,
        onProgress: (status, p) {
          progressStatusNotifier.value = status;
          progressValueNotifier.value = 0.6 + (p * 0.4);
        },
      );

      if (mounted) Navigator.of(context).pop(); // Close dialog

      await _loadAllSettings();

      if (mounted) {
        if (uploadRes['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Synced to Google Drive successfully! (${_formatFileSize(zipBytes.length)})'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Drive sync failed: ${uploadRes['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGDriveSyncing = false);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _startFreshOfflineApp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services, color: Colors.red),
            SizedBox(width: 8),
            Text('Fresh App Shuru Karein?'),
          ],
        ),
        content: const Text(
          'Yeh local cache ko poora reset/saaf kar dega taaki aap bilkul fresh app dekh sakein.\n\nFir aap "Restore Backup (Select File)" click karke backup file select karenge aur poora data turant wapas aa jayega.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear & Start Fresh'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LocalStorageService.clearAll(enableOfflineMode: true);
      if (mounted) {
        await _loadAllSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ App 100% fresh reset ho gayi (0 Orders)! Ab "Restore ZIP" se backup restore karein.'),
            backgroundColor: Colors.blueGrey,
            duration: Duration(seconds: 4),
          ),
        );
        HaroonTailorApp.restartApp(context);
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4. LANGUAGE & THEME ACTIONS
  // ──────────────────────────────────────────────────────────────────────────
  void _setTheme(String mode) async {
    setState(() => _currentTheme = mode);
    await LocalStorageService.saveAppTheme(mode);

    ThemeMode tm = ThemeMode.system;
    if (mode == 'light') tm = ThemeMode.light;
    if (mode == 'dark') tm = ThemeMode.dark;
    widget.onThemeChanged?.call(tm);
  }

  void _setLanguage(String lang) async {
    setState(() => _currentLanguage = lang);
    await LocalStorageService.saveAppLanguage(lang);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang == 'hi' ? 'Bhasha Hindi me badal di gayi hai!' : 'Language set to English!'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 5. SHOP PROFILE ACTIONS
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _saveShopProfile() async {
    final payload = {
      'shop_name': _shopNameCtrl.text.trim(),
      'owner_name': _ownerNameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'measurement_unit': _measurementUnit,
      'clothing_types': _clothingTypes.join(','),
    };

    await LocalStorageService.saveMeasurementUnit(_measurementUnit);
    await LocalStorageService.saveDefaultDeliveryDays(_defaultDeliveryDays);
    await LocalStorageService.saveDefaultRates(_defaultRates);

    await ApiService.updateShopSettings(payload);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop details aur preferences save ho gaye!'), backgroundColor: Colors.green),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD METHOD
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Settings (Settings & Preferences)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: const Color(0xFF3B82F6),
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.checkroom, size: 20), text: '1. Clothing Types'),
            Tab(icon: Icon(Icons.mark_chat_unread, size: 20), text: '2. Messages'),
            Tab(icon: Icon(Icons.cloud_sync, size: 20), text: '3. Backup & Sync'),
            Tab(icon: Icon(Icons.translate, size: 20), text: '4. Language'),
            Tab(icon: Icon(Icons.palette, size: 20), text: '5. Theme'),
            Tab(icon: Icon(Icons.edit_note, size: 20), text: '6. Notes Suggestions'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildClothingTypesTab(),
                _buildMessagesTab(),
                _buildBackupTab(),
                _buildLanguageTab(),
                _buildThemeTab(),
                _buildNotesSuggestionsTab(),
              ],
            ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 6. NOTES SUGGESTIONS ACTIONS & TAB
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _addNewNoteSuggestion(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final currentList = _clothingNotesMap[_selectedClothingTypeForNotes] ?? [];
    if (currentList.any((s) => s.toLowerCase() == clean.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yeh suggestion "$_selectedClothingTypeForNotes" me pehle se maujood hai!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    await LocalStorageService.addClothingNoteSuggestion(
      clothingType: _selectedClothingTypeForNotes,
      note: clean,
    );
    final updatedMap = await LocalStorageService.getClothingNotesMap();
    if (!mounted) return;
    setState(() {
      _clothingNotesMap = updatedMap;
      _newNoteCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Suggestion "$clean" ($_selectedClothingTypeForNotes) me jud gaya!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _removeNoteSuggestion(String item) async {
    await LocalStorageService.removeClothingNoteSuggestion(
      clothingType: _selectedClothingTypeForNotes,
      note: item,
    );
    final updatedMap = await LocalStorageService.getClothingNotesMap();
    if (!mounted) return;
    setState(() {
      _clothingNotesMap = updatedMap;
    });
  }

  Future<void> _resetNoteSuggestions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset "$_selectedClothingTypeForNotes" Suggestions?'),
        content: Text('Kya aap "$_selectedClothingTypeForNotes" ke note suggestions ko defaults par reset karna chahte hain?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LocalStorageService.resetClothingNotesSuggestions(clothingType: _selectedClothingTypeForNotes);
      final updatedMap = await LocalStorageService.getClothingNotesMap();
      if (!mounted) return;
      setState(() {
        _clothingNotesMap = updatedMap;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_selectedClothingTypeForNotes ke default suggestions restore ho gaye!'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Widget _buildNotesSuggestionsTab() {
    final currentList = _clothingNotesMap[_selectedClothingTypeForNotes] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Clothing Type Selector
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Clothing Type Chuniye (Select Garment)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text(
                    'Har kapde (jaise Shirt, Pant, Kurta) ki apni alag note suggestions hoti hain.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _clothingTypes.map((type) {
                        final isSelected = type.toLowerCase() == _selectedClothingTypeForNotes.toLowerCase();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(
                              Icons.check,
                              size: 16,
                              color: isSelected ? Colors.white : Colors.transparent,
                            ),
                            label: Text(
                              type,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF2563EB),
                            backgroundColor: const Color(0xFFF1F5F9),
                            onSelected: (sel) {
                              if (sel) {
                                setState(() => _selectedClothingTypeForNotes = type);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Add New Suggestion for selected clothing type
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nayi Tippani Jodein ($_selectedClothingTypeForNotes)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    'Order lete waqt jab aap "$_selectedClothingTypeForNotes" select karenge to yeh notes suggestions turant dikhenge.',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newNoteCtrl,
                          decoration: InputDecoration(
                            hintText: 'Jaise: Single Pocket, Chinese Collar, Slim Fitting...',
                            prefixIcon: const Icon(Icons.edit_note, size: 22),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onSubmitted: (v) => _addNewNoteSuggestion(v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _addNewNoteSuggestion(_newNoteCtrl.text),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Saved Note Suggestions List for selected clothing type
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '$_selectedClothingTypeForNotes Suggestions (${currentList.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Reset Defaults', style: TextStyle(fontSize: 12)),
                        onPressed: _resetNoteSuggestions,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (currentList.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('Koi suggestion nahi hai $_selectedClothingTypeForNotes ke liye. Upar se naya jodein.',
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: currentList.map((sugg) {
                        return Chip(
                          label: Text(sugg, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          backgroundColor: const Color(0xFFF1F5F9),
                          deleteIcon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                          onDeleted: () => _removeNoteSuggestion(sugg),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 1: CLOTHING TYPES
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildClothingTypesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Naya Kapda Jodein (Add Clothing Type)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newTypeCtrl,
                          decoration: InputDecoration(
                            hintText: 'Jaise: Safari, Sadri, Bandhgala...',
                            prefixIcon: const Icon(Icons.checkroom, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onSubmitted: (v) => _addNewClothingType(v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _addNewClothingType(_newTypeCtrl.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Jaldi Jodne Ke Liye Tap Karein (Quick Suggestions):', style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _suggestionChips.map((s) {
                      final exists = _clothingTypes.any((t) => t.toLowerCase() == s.toLowerCase());
                      return ActionChip(
                        avatar: Icon(exists ? Icons.check : Icons.add, size: 14, color: exists ? Colors.green : Colors.blueGrey),
                        label: Text(s, style: TextStyle(fontSize: 12, color: exists ? Colors.black54 : Colors.black87)),
                        backgroundColor: exists ? Colors.grey.shade200 : const Color(0xFFEFF6FF),
                        onPressed: exists ? null : () => _addNewClothingType(s),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Available Garments (${_clothingTypes.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              TextButton.icon(
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Reset Defaults', style: TextStyle(fontSize: 13)),
                onPressed: _resetClothingTypes,
              ),
            ],
          ),
          const SizedBox(height: 8),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _clothingTypes.length,
            itemBuilder: (ctx, idx) {
              final type = _clothingTypes[idx];
              final rate = _defaultRates[type] ?? 0.0;

              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    child: Text('${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  ),
                  title: Text(type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  subtitle: Text(rate > 0 ? 'Standard Rate: ₹${rate.toStringAsFixed(0)}' : 'Rate set nahi hai', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.currency_rupee, color: Color(0xFF2563EB), size: 18),
                        tooltip: 'Set default rate',
                        onPressed: () => _editDefaultRate(type, rate),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 18),
                        tooltip: 'Edit / Rename Garment',
                        onPressed: () => _editClothingType(type),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        tooltip: 'Delete Garment',
                        onPressed: () => _removeClothingType(type),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _editDefaultRate(String type, double curRate) async {
    final ctrl = TextEditingController(text: curRate > 0 ? curRate.toStringAsFixed(0) : '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$type Ka Default Rate'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Standard Silai Rate'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (confirmed == true) {
      final val = double.tryParse(ctrl.text.trim()) ?? 0.0;
      setState(() => _defaultRates[type] = val);
      await LocalStorageService.saveDefaultRates(_defaultRates);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 2: MESSAGE TEMPLATES
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildMessagesTab() {
    final preview = _formatPreviewText(_templateEditorCtrl.text);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WhatsApp & SMS Templates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Customer ko order, trial, ya baaki payment ke samay bheje jane wale messages yahan customize karein.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          const SizedBox(height: 14),

          // Template Selector Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTemplatePill('new_order', 'Naya Order (Confirmation)'),
                const SizedBox(width: 8),
                _buildTemplatePill('order_ready', 'Sil Kar Taiyar (Ready)'),
                const SizedBox(width: 8),
                _buildTemplatePill('delivered', 'Delivery Ho Gayi'),
                const SizedBox(width: 8),
                _buildTemplatePill('payment_reminder', 'Baaki Payment Reminder'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Editor Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Message Content', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      TextButton.icon(
                        icon: const Icon(Icons.restore, size: 14),
                        label: const Text('Default Template', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          final def = LocalStorageService.defaultMessageTemplates[_selectedTemplateKey] ?? '';
                          setState(() => _templateEditorCtrl.text = def);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _templateEditorCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  const Text('Insert Variables (Tap to add in text):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      '{customer_name}',
                      '{order_number}',
                      '{garments}',
                      '{delivery_date}',
                      '{total_amount}',
                      '{advance_amount}',
                      '{balance_amount}',
                      '{shop_name}',
                      '{shop_phone}',
                    ].map((varName) {
                      return ActionChip(
                        label: Text(varName, style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold)),
                        backgroundColor: const Color(0xFFEFF6FF),
                        onPressed: () => _insertPlaceholder(varName),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('Save Template', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saveCurrentTemplate,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Live Preview Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: const Color(0xFFE8F5E9),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.visibility, color: Color(0xFF2E7D32), size: 18),
                      SizedBox(width: 8),
                      Text('Customer Ko Aisa Dikhega (Live Preview)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(preview, style: const TextStyle(fontSize: 13, height: 1.4)),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.send, color: Colors.white, size: 16),
                    label: const Text('Test Send in WhatsApp', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                    onPressed: () {
                      PhoneUtils.openWhatsApp('', preview);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatePill(String key, String label) {
    final isSel = _selectedTemplateKey == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12)),
      selected: isSel,
      selectedColor: const Color(0xFF2563EB),
      backgroundColor: Colors.white,
      onSelected: (_) => _selectTemplate(key),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 3: BACKUP & SYNC
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildBackupTab() {
    final syncFormatted = _lastSyncTime != null
        ? '${_lastSyncTime!.day}/${_lastSyncTime!.month}/${_lastSyncTime!.year} ${_lastSyncTime!.hour}:${_lastSyncTime!.minute.toString().padLeft(2, '0')}'
        : 'Kabhi nahi (Never)';

    final String backupAvailability;
    if (_lastBackupTimeStr != null && _gDriveLastSyncTime != null) {
      backupAvailability = 'Available on Local Device & Google Drive';
    } else if (_lastBackupTimeStr != null) {
      backupAvailability = 'Available on Local Device Only';
    } else if (_gDriveLastSyncTime != null) {
      backupAvailability = 'Available on Google Drive Only';
    } else {
      backupAvailability = 'No backup created yet';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sync Status Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_done, color: Color(0xFF2563EB)),
                      SizedBox(width: 8),
                      Text('Cloud & Local Storage Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Cached Orders', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              Text('$_cachedOrdersCount Orders', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Cached Customers', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              Text('$_cachedCustomersCount Customers', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Last Sync: $syncFormatted', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Offline Standalone Mode Switch Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: _isOfflineMode ? Colors.amber.shade300 : Colors.blue.shade100,
                width: 1.5,
              ),
            ),
            elevation: 0,
            color: _isOfflineMode ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
            child: SwitchListTile(
              secondary: CircleAvatar(
                backgroundColor: _isOfflineMode ? const Color(0xFFFEF3C7) : const Color(0xFFEFF6FF),
                child: Icon(
                  _isOfflineMode ? Icons.cloud_off : Icons.cloud_done,
                  color: _isOfflineMode ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                ),
              ),
              title: Text(
                _isOfflineMode ? '📶 Offline Standalone Mode (ON)' : '☁️ Cloud Sync Mode (Active)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _isOfflineMode ? const Color(0xFF92400E) : const Color(0xFF1E40AF),
                ),
              ),
              subtitle: Text(
                _isOfflineMode
                    ? 'Cloud server sync band hai. App 100% local database par chal rahi hai (Render se data nahi aayega).'
                    : 'App Render cloud server se auto-sync ho rahi hai.',
                style: const TextStyle(fontSize: 12),
              ),
              value: _isOfflineMode,
              activeThumbColor: const Color(0xFFD97706),
              onChanged: (val) async {
                await LocalStorageService.setOfflineMode(val);
                setState(() => _isOfflineMode = val);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(val ? 'Offline Standalone Mode ON! Cloud sync paused.' : 'Cloud Sync Mode ON! Auto-sync active.'),
                      backgroundColor: val ? Colors.amber.shade800 : Colors.blue,
                    ),
                  );
                  HaroonTailorApp.restartApp(context);
                }
              },
            ),
          ),
          const SizedBox(height: 16),

          // ★ PRIMARY: SMART SINGLE-FILE BACKUP (DATA + PHOTOS + SETTINGS)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.archive, color: Colors.white, size: 24),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '📦 Smart Backup (Local & Google Drive)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'File: "HaroonTailor_Backup.zip" — Complete orders, naap measurements, photos & settings.',
                              style: TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Storage Location & Details Badge
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _lastBackupTimeStr != null || _gDriveLastSyncTime != null
                                  ? Icons.check_circle
                                  : Icons.info_outline,
                              size: 16,
                              color: _lastBackupTimeStr != null ? const Color(0xFF86EFAC) : Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                backupAvailability,
                                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (_lastBackupSizeBytes != null)
                              Text(
                                _formatFileSize(_lastBackupSizeBytes!),
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                              ),
                          ],
                        ),
                        const Divider(color: Colors.white24, height: 16),
                        _buildLocationRow(Icons.folder, 'Local File', _lastBackupPath ?? 'haroon_tailor_app/storage/HaroonTailor_Backup.zip'),
                        const SizedBox(height: 4),
                        _buildLocationRow(
                          Icons.cloud,
                          'Drive File',
                          _gDriveConnected ? 'Google Drive: My Drive / HaroonTailor_Backup.zip' : 'Google Drive: Not Connected',
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Local: ${_formatBackupDate(_lastBackupTimeStr)}',
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Cloud: ${_formatBackupDate(_gDriveLastSyncTime)}',
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isBackingUp
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C3AED)))
                              : const Icon(Icons.sync, size: 20),
                          label: const Text('Backup Now', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF7C3AED),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isBackingUp ? null : _downloadZipBackup,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.unarchive, size: 20),
                          label: const Text('Restore Data', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Colors.white30),
                            ),
                          ),
                          onPressed: _isBackingUp ? null : _restoreFromZipFile,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ★ GOOGLE DRIVE AUTO-BACKUP & SYNC CARD
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.cloud_sync, color: Color(0xFF2563EB), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Google Drive Auto Backup & Sync',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                            ),
                            Text(
                              _gDriveConnected
                                  ? 'Connected as: ${_gDriveEmail ?? "Google Account"}'
                                  : 'Not connected. Connect to auto-sync your data.',
                              style: TextStyle(
                                fontSize: 12,
                                color: _gDriveConnected ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                fontWeight: _gDriveConnected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gDriveConnected ? Colors.red : const Color(0xFF2563EB),
                          side: BorderSide(color: _gDriveConnected ? Colors.red.shade200 : const Color(0xFF2563EB)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _gDriveConnected ? _disconnectGoogleDrive : _connectGoogleDriveDialog,
                        child: Text(_gDriveConnected ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                  if (_gDriveConnected) ...[
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Backup to Google Drive', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: const Text(
                        'Automatically backs up orders and data changes in background (debounced).',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      value: _gDriveAutoSync,
                      activeThumbColor: const Color(0xFF2563EB),
                      onChanged: (val) async {
                        await GoogleDriveService.setAutoSyncEnabled(val);
                        setState(() => _gDriveAutoSync = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Status: $_gDriveSyncStatus',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: _isGDriveSyncing
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.cloud_upload, size: 16),
                          label: const Text('Sync to Drive Now', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isGDriveSyncing ? null : _syncToGoogleDriveNow,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Testing & Reset
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEF2F2),
                    child: Icon(Icons.cleaning_services, color: Colors.red),
                  ),
                  title: const Text('Start Fresh Offline App (Clear All Data)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  subtitle: const Text('App ko khali karke fresh chalu karein taaki aap restore test kar sakein.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _startFreshOfflineApp,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 4: LANGUAGE
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildLanguageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('App Bhasha Chuniye (Select Language)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Aapki suvidha ke hisab se app ki bhasha set karein.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          const SizedBox(height: 16),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('English (Default)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Orders, Measurements, Customers, Deliveries'),
                  value: 'en',
                  groupValue: _currentLanguage,
                  onChanged: (v) => _setLanguage(v!),
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  title: const Text('हिन्दी / Hinglish (Tailor Terminology)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Naap, Silai, Baaki Hissab, Grahak, Kapda, Karigar'),
                  value: 'hi',
                  groupValue: _currentLanguage,
                  onChanged: (v) => _setLanguage(v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Suggested Feature: Measurement Unit
          const Text('Suggested: Measurement Unit (Naap Ki Ikai)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _measurementUnit,
                    decoration: InputDecoration(
                      labelText: 'Standard Measurement Unit',
                      prefixIcon: const Icon(Icons.straighten),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: ['Inches (in)', 'Centimeters (cm)', 'Meters (m)']
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _measurementUnit = val);
                        LocalStorageService.saveMeasurementUnit(val);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 5: THEME
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildThemeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Theme & Appearance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Apni pasand ke anusar dark ya light theme chuniye.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          const SizedBox(height: 16),

          Row(
            children: [
              _buildThemeCard('system', 'System', Icons.settings_brightness, const Color(0xFF64748B)),
              const SizedBox(width: 10),
              _buildThemeCard('light', 'Light Mode', Icons.light_mode, Colors.amber),
              const SizedBox(width: 10),
              _buildThemeCard('dark', 'Dark Mode', Icons.dark_mode, const Color(0xFF0F172A)),
            ],
          ),
          const SizedBox(height: 24),

          // Suggested Shop Profile & Invoicing
          const Text('Suggested: Shop Profile & Invoicing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Receipts aur bills par print hone wali dukaan ki details.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          const SizedBox(height: 12),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _shopNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Dukaan Ka Naam (Shop Name)',
                      prefixIcon: const Icon(Icons.store),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ownerNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Malik Ka Naam (Owner Name)',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone / WhatsApp Number',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Dukaan Ka Pata (Address)',
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text('Save Shop Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saveShopProfile,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard(String mode, String title, IconData icon, Color color) {
    final isSelected = _currentTheme == mode;

    return Expanded(
      child: InkWell(
        onTap: () => _setTheme(mode),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2)),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isSelected ? const Color(0xFF2563EB) : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
