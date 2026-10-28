import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import 'order_details_screen.dart';
import 'pending_payments_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int) onTabChange;
  const DashboardScreen({super.key, required this.onTabChange});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<dynamic> _recentOrders = [];

  void reloadDashboard() {
    _loadDashboard();
  }

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard({bool showLoading = true}) async {
    // 1. Instant local cache load (0 milliseconds delay!)
    final cached = await LocalStorageService.getCachedDashboardStats();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _stats = cached;
        _recentOrders = cached['recent_orders'] ?? [];
        _isLoading = false;
      });
    } else if (showLoading && _stats.isEmpty) {
      setState(() => _isLoading = true);
    }

    // 2. Fetch fresh updates from server in background
    try {
      final data = await ApiService.getDashboardStats();
      if (!mounted) return;
      setState(() {
        _stats = data;
        _recentOrders = data['recent_orders'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (_stats.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load dashboard: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final today = DateFormat('EEEE, d MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Haroon Tailor',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
            Text(
              today,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.amberAccent),
            tooltip: 'Pending Payments List',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PendingPaymentsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadDashboard,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KPI Row
                    Row(
                      children: [
                        Expanded(
                          child: _buildKpiCard(
                            title: "Today's Orders",
                            value: '${_stats['orders_today'] ?? 0}',
                            icon: Icons.receipt_long,
                            color: const Color(0xFF2563EB),
                            onTap: () => widget.onTabChange(1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildKpiCard(
                            title: 'Deliveries Due',
                            value: '${_stats['deliveries_today'] ?? 0}',
                            icon: Icons.local_shipping,
                            color: const Color(0xFFD97706),
                            onTap: () => widget.onTabChange(2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildKpiCard(
                      title: 'Total Pending Balance (Tap for List)',
                      value: currency.format(_stats['pending_payments'] ?? _stats['pending_balance'] ?? 0),
                      icon: Icons.account_balance_wallet,
                      color: const Color(0xFF059669),
                      isFullWidth: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PendingPaymentsScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Quick Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Orders',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                        TextButton(
                          onPressed: () => widget.onTabChange(1),
                          child: const Text('View All', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Recent Orders List
                    if (_recentOrders.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text('No orders yet', style: TextStyle(color: Colors.grey.shade500)),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final o = _recentOrders[index];
                          final status = o['status']?.toString() ?? 'NEW';
                          int orderId = (o['id'] is int)
                              ? o['id'] as int
                              : int.tryParse(o['id']?.toString() ?? '0') ?? 0;
                          if (orderId <= 0) {
                            final bDigits = RegExp(r'\d+').allMatches((o['order_number'] ?? '').toString()).lastOrNull?.group(0);
                            if (bDigits != null) orderId = int.tryParse(bDigits) ?? 0;
                          }

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OrderDetailsScreen(
                                      orderId: orderId,
                                      onOrderUpdated: _loadDashboard,
                                    ),
                                  ),
                                );
                                _loadDashboard();
                              },
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(status).withOpacity(0.12),
                                child: Icon(Icons.shopping_bag, color: _getStatusColor(status), size: 20),
                              ),
                              title: Text(
                                o['customer_name']?.toString() ?? 'Customer',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              subtitle: Text(
                                o['order_number']?.toString() ?? '',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  status.replaceAll('_', ' '),
                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isFullWidth = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'DELIVERED':
        return const Color(0xFF059669);
      case 'STITCHING_COMPLETE':
        return const Color(0xFF0284C7);
      case 'PARTIALLY_DELIVERED':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF64748B);
    }
  }
}
