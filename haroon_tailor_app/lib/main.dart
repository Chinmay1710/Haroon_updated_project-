import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/dashboard_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/deliveries_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/new_order_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/pending_payments_screen.dart';
import 'services/local_storage_service.dart';
import 'services/zip_backup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorageService.initStorage();
  ZipBackupService.registerAutoSyncHook();
  ZipBackupService.checkAndPerformAutoBackup().ignore();
  runApp(const HaroonTailorApp());
}

class HaroonTailorApp extends StatefulWidget {
  const HaroonTailorApp({super.key});

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_HaroonTailorAppState>()?.restartApp();
  }

  @override
  State<HaroonTailorApp> createState() => _HaroonTailorAppState();
}

class _HaroonTailorAppState extends State<HaroonTailorApp> {
  Key _key = UniqueKey();
  ThemeMode _themeMode = ThemeMode.light;

  void restartApp() {
    setState(() {
      _key = UniqueKey();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final theme = await LocalStorageService.getAppTheme();
    if (mounted) {
      setState(() {
        if (theme == 'dark') {
          _themeMode = ThemeMode.dark;
        } else {
          _themeMode = ThemeMode.light;
        }
      });
    }
  }

  void _handleThemeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: MaterialApp(
        title: 'Haroon Tailor',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0F172A),
            primary: const Color(0xFF0F172A),
            secondary: const Color(0xFF2563EB),
            surface: Colors.white,
          ),
          textTheme: GoogleFonts.publicSansTextTheme(Theme.of(context).textTheme),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF131418),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            brightness: Brightness.dark,
            primary: const Color(0xFF3B82F6),
            secondary: const Color(0xFF60A5FA),
            surface: const Color(0xFF1E1F24),
          ),
          textTheme: GoogleFonts.publicSansTextTheme(ThemeData.dark().textTheme),
        ),
        home: MainNavigationScreen(onThemeChanged: _handleThemeChanged),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final ValueChanged<ThemeMode>? onThemeChanged;
  const MainNavigationScreen({super.key, this.onThemeChanged});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final GlobalKey<DashboardScreenState> _dashboardKey = GlobalKey<DashboardScreenState>();
  final GlobalKey<OrdersScreenState> _ordersKey = GlobalKey<OrdersScreenState>();
  final GlobalKey<DeliveriesScreenState> _deliveriesKey = GlobalKey<DeliveriesScreenState>();
  final GlobalKey<CustomersScreenState> _customersKey = GlobalKey<CustomersScreenState>();

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    if (index == 0) _dashboardKey.currentState?.reloadDashboard();
    if (index == 1) _ordersKey.currentState?.reloadOrders();
    if (index == 2) _deliveriesKey.currentState?.reloadDeliveries();
    if (index == 3) _customersKey.currentState?.reloadCustomers();
  }

  void _openNewOrder() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewOrderScreen(
          onOrderCreated: () {
            setState(() => _currentIndex = 1); // switch to orders tab
            _ordersKey.currentState?.switchToAllOrders();
            _ordersKey.currentState?.reloadOrders();
            _deliveriesKey.currentState?.reloadDeliveries();
            _dashboardKey.currentState?.reloadDashboard();
          },
        ),
      ),
    );
    if (res == true) {
      setState(() => _currentIndex = 1);
      _ordersKey.currentState?.switchToAllOrders();
      _ordersKey.currentState?.reloadOrders();
      _deliveriesKey.currentState?.reloadDeliveries();
      _dashboardKey.currentState?.reloadDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(key: _dashboardKey, onTabChange: _onTabTapped),
      OrdersScreen(key: _ordersKey),
      DeliveriesScreen(key: _deliveriesKey),
      CustomersScreen(key: _customersKey),
      SettingsScreen(onThemeChanged: widget.onThemeChanged),
    ];

    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF0F172A)),
              accountName: Text('Haroon Tailor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              accountEmail: Text('Smart Tailor Management System', style: TextStyle(color: Colors.white70)),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Color(0xFF2563EB),
                child: Icon(Icons.checkroom, color: Colors.white, size: 36),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home Dashboard'),
              selected: _currentIndex == 0,
              onTap: () {
                Navigator.pop(context);
                _onTabTapped(0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Orders'),
              selected: _currentIndex == 1,
              onTap: () {
                Navigator.pop(context);
                _onTabTapped(1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text('Deliveries'),
              selected: _currentIndex == 2,
              onTap: () {
                Navigator.pop(context);
                _onTabTapped(2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Customers & Naap'),
              selected: _currentIndex == 3,
              onTap: () {
                Navigator.pop(context);
                _onTabTapped(3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined, color: Colors.amber),
              title: const Text('Pending Payments'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingPaymentsScreen()));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings, color: Color(0xFF2563EB)),
              title: const Text('Settings (Settings & Preferences)', style: TextStyle(fontWeight: FontWeight.bold)),
              selected: _currentIndex == 4,
              onTap: () {
                Navigator.pop(context);
                _onTabTapped(4);
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'main_new_order_fab',
        backgroundColor: const Color(0xFF2563EB),
        elevation: 4,
        shape: const CircleBorder(),
        onPressed: _openNewOrder,
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        elevation: 10,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home, 'Home', 0),
            _buildNavItem(Icons.receipt_long, 'Orders', 1),
            const SizedBox(width: 48), // Space for floating center button
            _buildNavItem(Icons.local_shipping, 'Deliveries', 2),
            _buildNavItem(Icons.people, 'Customers', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B);

    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
