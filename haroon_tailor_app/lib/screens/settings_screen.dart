import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../services/zip_backup_service.dart';
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

  List<String> _notesSuggestions = [];
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
      final notesSugg = await LocalStorageService.getNotesSuggestions();
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
        _notesSuggestions = notesSugg;
        _lastBackupTimeStr = bTime;
        _lastBackupSizeBytes = bSize;
        _lastBackupPath = bPath;

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
      final zipBytes = await FileHelper.pickBackupZipFile();
      if (zipBytes == null) return; // User cancelled
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
                Text('Restoring ZIP Backup'),
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
                Text('ZIP Backup Restored!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aapki ZIP backup se poora data + photos restore ho gaye:'),
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
                          'Photos + Data sab 100% offline! Cloudinary ki zarurat nahi!',
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
            content: Text('ZIP Restore error: ${res['error'] ?? "Invalid ZIP file"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        try { Navigator.of(context).pop(); } catch (_) {}
        setState(() => _isBackingUp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ZIP File error: $e'), backgroundColor: Colors.red),
        );
      }
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
    if (_notesSuggestions.any((s) => s.toLowerCase() == clean.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ye suggestion pehle se maujood hai!'), backgroundColor: Colors.orange),
      );
      return;
    }
    final updated = List<String>.from(_notesSuggestions)..add(clean);
    await LocalStorageService.saveNotesSuggestions(updated);
    setState(() {
      _notesSuggestions = updated;
      _newNoteCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Suggestion "$clean" jud gaya!'), backgroundColor: Colors.green),
    );
  }

  Future<void> _removeNoteSuggestion(String item) async {
    final updated = List<String>.from(_notesSuggestions)..removeWhere((s) => s == item);
    await LocalStorageService.saveNotesSuggestions(updated);
    setState(() => _notesSuggestions = updated);
  }

  Future<void> _resetNoteSuggestions() async {
    await LocalStorageService.saveNotesSuggestions(List.from(LocalStorageService.defaultNotesSuggestions));
    final updated = await LocalStorageService.getNotesSuggestions();
    setState(() => _notesSuggestions = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Default suggestions restore ho gaye!'), backgroundColor: Colors.blue),
    );
  }

  Widget _buildNotesSuggestionsTab() {
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
                  const Text('Nayi Tippani Jodein (Add Note Suggestion)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text(
                    'Kapda darj karte waqt "Vishesh Tippani (Notes)" me ye suggestions turant chips ke roop me dikhenge.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newNoteCtrl,
                          decoration: InputDecoration(
                            hintText: 'Jaise: Collar Chinese, 2 Pocket, Fitting Slim...',
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
                      Text(
                        'Saved Note Suggestions (${_notesSuggestions.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Reset Defaults', style: TextStyle(fontSize: 12)),
                        onPressed: _resetNoteSuggestions,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_notesSuggestions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('Koi suggestion nahi hai. Upar se naya jodein.', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _notesSuggestions.map((sugg) {
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
                              '📦 Smart Single Backup (Data + Photos + Settings)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Hamesha ek hi file update hoti hai ("HaroonTailor_Backup.zip"). Duplicate files nahi banti aur backup super fast hota hai.',
                              style: TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Last Backup Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            _lastBackupTimeStr != null ? Icons.check_circle : Icons.info_outline,
                            size: 16,
                            color: _lastBackupTimeStr != null ? const Color(0xFF86EFAC) : Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lastBackupTimeStr != null
                                    ? 'Last Backup: ${_formatBackupDate(_lastBackupTimeStr)}  •  ${_lastBackupSizeBytes != null ? _formatFileSize(_lastBackupSizeBytes!) : ""}'
                                    : 'Status: Abhi tak koi backup nahi liya gaya.',
                                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              if (_lastBackupPath != null && _lastBackupPath!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Path: $_lastBackupPath',
                                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
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
                          label: const Text('Restore ZIP', style: TextStyle(fontWeight: FontWeight.bold)),
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
