import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/phone_utils.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool _isLoading = true;
  List<dynamic> _allOrders = [];
  List<dynamic> _filteredOrders = [];
  String _selectedStatus = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService.getAllOrders();
      setState(() {
        _allOrders = list;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load orders: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    _filteredOrders = _allOrders.where((o) {
      final status = (o['status']?.toString() ?? 'NEW');
      bool matchesStatus = true;
      if (_selectedStatus == 'INCOMPLETE') {
        matchesStatus = status != 'DELIVERED' && status != 'CANCELLED' && status != 'STITCHING_COMPLETE';
      } else if (_selectedStatus == 'STITCHING_COMPLETE') {
        matchesStatus = status == 'STITCHING_COMPLETE';
      } else if (_selectedStatus == 'DELIVERED') {
        matchesStatus = status == 'DELIVERED';
      }

      if (!matchesStatus) return false;

      if (q.isNotEmpty) {
        final custName = (o['customer_name'] ?? '').toString().toLowerCase();
        final billNo = (o['order_number'] ?? '').toString().toLowerCase();
        final phone = (o['customer_mobile'] ?? '').toString().toLowerCase();
        return custName.contains(q) || billNo.contains(q) || phone.contains(q);
      }
      return true;
    }).toList();
  }

  void _updateStatus(int orderId, String newStatus) async {
    try {
      await ApiService.updateOrderStatus(orderId: orderId, status: newStatus, sendWhatsapp: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to ${newStatus.replaceAll('_', ' ')}'), backgroundColor: Colors.green),
        );
      }
      _loadOrders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteOrder(Map<String, dynamic> order) async {
    final orderId = order['id'] as int;
    final billNo = order['order_number'] ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Order $billNo?'),
        content: Text(
          'Kya aap sach me order $billNo delete karna chahte hain?\n'
          'Yeh bill number agle naye order ke liye dobara reuse hoga.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.deleteOrder(orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order $billNo delete ho gaya.'), backgroundColor: Colors.red),
          );
        }
        _loadOrders();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete fail: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _shareWhatsAppReminder(Map<String, dynamic> order) {
    final phone = (order['customer_mobile'] ?? '').toString();
    final billNo = order['order_number'] ?? '';
    final custName = order['customer_name'] ?? '';
    final remaining = order['remaining_amount'] ?? 0;

    final msg =
        'Assalam-o-Alaikum $custName ji,\n'
        'Haroon Tailor se aapka order ($billNo) taiyar hai.\n'
        'Baqaya Rakam: ₹$remaining\n'
        'Shukriya!';

    PhoneUtils.openWhatsApp(phone: phone, message: msg);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Orders Directory', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(_applyFilter),
              decoration: InputDecoration(
                hintText: 'Search order number, customer name...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('ALL', 'All Orders'),
                _buildFilterChip('INCOMPLETE', 'Incomplete'),
                _buildFilterChip('STITCHING_COMPLETE', 'Stitched'),
                _buildFilterChip('DELIVERED', 'Delivered'),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                : _filteredOrders.isEmpty
                    ? Center(child: Text('No orders found', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)))
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredOrders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final o = Map<String, dynamic>.from(_filteredOrders[index]);
                            final orderId = o['id'] as int;
                            final status = o['status']?.toString() ?? 'NEW';
                            final total = o['total_amount'] ?? 0;
                            final remaining = o['remaining_amount'] ?? 0;
                            final billNo = o['order_number']?.toString() ?? 'Bill-#$orderId';
                            final custName = o['customer_name']?.toString() ?? 'Unknown';
                            final phone = (o['customer_mobile'] ?? '').toString();

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  // Open complete order details (Point 8)
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OrderDetailsScreen(
                                        orderId: orderId,
                                        onOrderUpdated: _loadOrders,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            billNo,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                                          ),
                                          Container(
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
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        custName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      if (phone.isNotEmpty)
                                        Text(phone, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                      if (o['delivery_date'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            'Delivery: ${o['delivery_date'].toString().split('T')[0]}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          ),
                                        ),
                                      const Divider(height: 18),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Total: ${currency.format(total)}',
                                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                              if (remaining > 0)
                                                Text('Due: ${currency.format(remaining)}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13))
                                              else
                                                const Text('Paid',
                                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                                            ],
                                          ),
                                          // ACTION BUTTONS (Point 3: Complete, Partial, Delete, WhatsApp)
                                          Row(
                                            children: [
                                              // WhatsApp Reminder
                                              IconButton(
                                                icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 20),
                                                tooltip: 'Send WhatsApp Reminder',
                                                onPressed: () => _shareWhatsAppReminder(o),
                                              ),

                                              // Partial Button
                                              if (status != 'STITCHING_COMPLETE' && status != 'DELIVERED')
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 6),
                                                  child: OutlinedButton(
                                                    style: OutlinedButton.styleFrom(
                                                      side: const BorderSide(color: Color(0xFFD97706)),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    onPressed: () => _updateStatus(orderId, 'PARTIALLY_COMPLETE'),
                                                    child: const Text('Partial',
                                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                                                  ),
                                                ),

                                              // Complete Button
                                              if (status != 'STITCHING_COMPLETE' && status != 'DELIVERED')
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 6),
                                                  child: ElevatedButton(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF0F172A),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    onPressed: () => _updateStatus(orderId, 'STITCHING_COMPLETE'),
                                                    child: const Text('Complete',
                                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                                  ),
                                                ),

                                              // Delete Button
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                                tooltip: 'Delete Order',
                                                onPressed: () => _deleteOrder(o),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF0F172A),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _selectedStatus = value;
              _applyFilter();
            });
          }
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'DELIVERED':
        return Colors.green;
      case 'STITCHING_COMPLETE':
        return Colors.blue;
      case 'PARTIALLY_COMPLETE':
        return Colors.orange;
      default:
        return Colors.purple;
    }
  }
}
