import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/customer.dart';

class CustomersScreen extends StatefulWidget {
  final Function(Customer)? onSelectCustomer;
  const CustomersScreen({super.key, this.onSelectCustomer});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  bool _isLoading = true;
  List<Customer> _allCustomers = [];
  List<Customer> _filteredCustomers = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getCustomers();
      final list = data.map((c) => Customer.fromJson(c)).toList();
      setState(() {
        _allCustomers = list;
        _filteredCustomers = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load customers: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filteredCustomers = _allCustomers);
      return;
    }
    final cleanQ = q.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _filteredCustomers = _allCustomers.where((c) {
        final matchesName = c.name.toLowerCase().contains(q);
        final matchesPhone = c.mobile.contains(q) || (cleanQ.isNotEmpty && c.cleanMobile.contains(cleanQ));
        return matchesName || matchesPhone;
      }).toList();
    });
  }

  void _showAddCustomerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? duplicateWarning;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void checkDuplicate(String val) {
              final clean = val.replaceAll(RegExp(r'\D'), '');
              if (clean.length == 10) {
                final match = _allCustomers.firstWhere(
                  (c) => c.cleanMobile == clean,
                  orElse: () => Customer(id: 0, name: '', mobile: ''),
                );
                if (match.id != 0) {
                  setModalState(() {
                    duplicateWarning = 'Yeh number pehle se "${match.name}" ke paas hai! Duplicate allow nahi hai.';
                  });
                  return;
                }
              }
              setModalState(() {
                duplicateWarning = null;
              });
            }

            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Add New Customer',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Customer Full Name *',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      onChanged: checkDuplicate,
                      decoration: InputDecoration(
                        labelText: '10-Digit Mobile Number *',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    if (duplicateWarning != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                duplicateWarning!,
                                style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressCtrl,
                      decoration: InputDecoration(
                        labelText: 'Address (Optional)',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                        labelText: 'Client Notes (Optional)',
                        prefixIcon: const Icon(Icons.note_alt_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: duplicateWarning != null || isSaving
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                final rawPhone = phoneCtrl.text.trim();
                                final cleanPhone = rawPhone.replaceAll(RegExp(r'\D'), '');

                                if (name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Customer name is required')),
                                  );
                                  return;
                                }
                                if (cleanPhone.length != 10) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Mobile number must be 10 digits')),
                                  );
                                  return;
                                }

                                setModalState(() => isSaving = true);
                                try {
                                  final res = await ApiService.createCustomer(
                                    name: name,
                                    mobile: '+91 $cleanPhone',
                                    address: addressCtrl.text.trim(),
                                    notes: notesCtrl.text.trim(),
                                  );
                                  Navigator.pop(ctx);
                                  _loadCustomers();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Customer "${res['name'] ?? name}" saved!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (err) {
                                  setModalState(() => isSaving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
                                  );
                                }
                              },
                        child: isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Save Customer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Customers (Grahak)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add Customer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: _showAddCustomerDialog,
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name or mobile number...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                : _filteredCustomers.isEmpty
                    ? Center(
                        child: Text(
                          'No customers found',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCustomers,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredCustomers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final c = _filteredCustomers[index];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: ListTile(
                                onTap: widget.onSelectCustomer != null
                                    ? () => widget.onSelectCustomer!(c)
                                    : null,
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF0F172A).withOpacity(0.08),
                                  child: Text(
                                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: Text(
                                  c.mobile.isNotEmpty ? c.mobile : 'No phone number',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                trailing: widget.onSelectCustomer != null
                                    ? const Icon(Icons.check_circle_outline, color: Color(0xFF0F172A))
                                    : const Icon(Icons.chevron_right, color: Colors.grey),
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
}
