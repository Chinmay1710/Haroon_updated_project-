import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../utils/phone_utils.dart';

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

  // 4. Language & Theme
  String _currentTheme = 'system';
  String _currentLanguage = 'en';

  // 5. Shop Profile & Defaults
  final TextEditingController _shopNameCtrl = TextEditingController();
  final TextEditingController _ownerNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  String _measurementUnit = 'Inches (in)';
  int _defaultDeliveryDays = 7;
  Map<String, double> _defaultRates = {};

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
    _tabController = TabController(length: 5, vsync: this);
    _loadAllSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _newTypeCtrl.dispose();
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
  Future<void> _exportLocalBackup() async {
    final jsonStr = await LocalStorageService.exportLocalBackupJson();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.download, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Local Data Backup (JSON)'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Yeh backup aapke sabhi offline orders, customers aur naap ka snapshot hai.'),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    jsonStr,
                    style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy to Clipboard'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Backup JSON clipboard me copy ho gaya!'), backgroundColor: Colors.green),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalBackup() async {
    final textCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Data from Backup JSON'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Apna pehle se copy kiya gaya backup JSON yahan paste karein:'),
            const SizedBox(height: 10),
            TextField(
              controller: textCtrl,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '{\n  "clothing_types": [...],\n  ...\n}',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore Data'),
          ),
        ],
      ),
    );

    if (confirmed == true && textCtrl.text.trim().isNotEmpty) {
      final success = await LocalStorageService.importLocalBackupJson(textCtrl.text.trim());
      if (success) {
        await _loadAllSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup successfully restore ho gaya!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid JSON format! Restore fail ho gaya.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _triggerServerBackup() async {
    setState(() => _isBackingUp = true);
    final res = await ApiService.createDatabaseBackup();
    setState(() => _isBackingUp = false);

    if (!mounted) return;
    if (res['status'] == 'success') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cloud_done, color: Colors.green),
              SizedBox(width: 8),
              Text('Server Backup Complete'),
            ],
          ),
          content: Text(
            'Database backup create ho chuka hai!\n\nFile Path:\n${res['data']?['backup_path'] ?? 'Server Storage'}',
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Server backup failed!'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _clearLocalCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Offline Cache Clear Karein?'),
        content: const Text(
          'Offline cached data delete ho jayega. Agli baar internet se fresh data download hoga. Database safe rahega.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Cache', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LocalStorageService.clearAll();
      await _loadAllSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Local cache clear ho gaya!'), backgroundColor: Colors.blueGrey),
        );
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

          // Actions
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFEFF6FF), child: Icon(Icons.download, color: Color(0xFF2563EB))),
                  title: const Text('Export Local JSON Backup', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Copy or download all offline customer & order data snapshot.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportLocalBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFF0FDF4), child: Icon(Icons.upload, color: Color(0xFF16A34A))),
                  title: const Text('Restore Data from Backup', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Paste backup JSON to restore all measurements and history.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _importLocalBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFFAF5FF),
                    child: _isBackingUp ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.storage, color: Color(0xFF9333EA)),
                  ),
                  title: const Text('Trigger Server Database Backup (.ZIP)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Server SQLite DB and attachments zipped into hard drive/drive.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isBackingUp ? null : _triggerServerBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFFEF2F2), child: Icon(Icons.delete_sweep, color: Colors.red)),
                  title: const Text('Clear Local Cache', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  subtitle: const Text('Clear local cached files to force re-download from server.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _clearLocalCache,
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
