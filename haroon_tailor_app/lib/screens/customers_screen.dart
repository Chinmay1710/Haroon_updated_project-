import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../models/customer.dart';
import 'customer_details_screen.dart';
import 'new_order_screen.dart';

class CustomersScreen extends StatefulWidget {
  final bool isSelectMode;
  final Function(Customer)? onSelectCustomer;

  const CustomersScreen({
    super.key,
    this.isSelectMode = false,
    this.onSelectCustomer,
  });

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

  Future<void> _loadCustomers({bool showLoading = true}) async {
    // 1. Instant local cache load (0 milliseconds delay!)
    final cached = await LocalStorageService.getCachedCustomers();
    if (cached != null && cached.isNotEmpty && mounted) {
      final list = cached.map((c) => Customer.fromJson(c)).toList();
      setState(() {
        _allCustomers = list;
        _filteredCustomers = list;
        _isLoading = false;
      });
    } else if (showLoading && _allCustomers.isEmpty) {
      setState(() => _isLoading = true);
    }

    // 2. Fetch fresh updates from server in background
    try {
      final data = await ApiService.getCustomers();
      final list = data.map((c) => Customer.fromJson(c)).toList();
      if (mounted) {
        setState(() {
          _allCustomers = list;
          _filteredCustomers = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (_allCustomers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load customers: $e'), backgroundColor: Colors.red),
          );
        }
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
    String? phoneError;
    String? phoneHelper = '10 ank ka mobile number dalein';
    bool isPhoneValid = false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void validatePhone(String val) {
              final clean = val.replaceAll(RegExp(r'\D'), '');
              if (clean.isEmpty) {
                phoneError = null;
                phoneHelper = '10 ank ka mobile number dalein';
                isPhoneValid = false;
              } else if (!['6', '7', '8', '9'].contains(clean[0])) {
                phoneError = 'Mobile number 6, 7, 8 ya 9 se shuru hona chahiye';
                phoneHelper = null;
                isPhoneValid = false;
              } else if (clean.length < 10) {
                phoneError = null;
                phoneHelper = '${clean.length}/10 ank darj kiye (10 ank zaroori)';
                isPhoneValid = false;
              } else {
                // Exactly 10 digits starting with 6-9
                final match = _allCustomers.firstWhere(
                  (c) => c.cleanMobile == clean,
                  orElse: () => Customer(id: 0, name: '', mobile: ''),
                );
                if (match.id != 0) {
                  phoneError = 'Yeh number pehle se "${match.name}" ke paas hai! Duplicate allow nahi hai.';
                  phoneHelper = null;
                  isPhoneValid = false;
                } else {
                  phoneError = null;
                  phoneHelper = 'Sahi mobile number ✓';
                  isPhoneValid = true;
                }
              }
              setModalState(() {});
            }

            final canSave = !isSaving && isPhoneValid && nameCtrl.text.trim().isNotEmpty && phoneError == null;

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
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
                      ],
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Customer Full Name *',
                        hintText: 'Jaise: Mohammad Rashid',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      onChanged: validatePhone,
                      decoration: InputDecoration(
                        labelText: '10-Digit Mobile Number *',
                        prefixText: '+91 ',
                        prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 16),
                        prefixIcon: const Icon(Icons.phone_outlined),
                        errorText: phoneError,
                        errorMaxLines: 2,
                        helperText: phoneError == null ? phoneHelper : null,
                        helperStyle: TextStyle(
                          color: isPhoneValid ? Colors.green.shade700 : Colors.grey.shade600,
                          fontWeight: isPhoneValid ? FontWeight.bold : FontWeight.normal,
                        ),
                        suffixIcon: isPhoneValid
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : (phoneError != null
                                ? const Icon(Icons.error_outline, color: Colors.red)
                                : Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                                    child: Text(
                                      '${phoneCtrl.text.replaceAll(RegExp(r"\D"), "").length}/10',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                    ),
                                  )),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    Row(
                      children: [
                        // 1. SAVE CUSTOMER ONLY
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: canSave ? const Color(0xFF0F172A) : Colors.grey.shade300,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: !canSave
                                  ? null
                                  : () async {
                                      final name = nameCtrl.text.trim();
                                      final cleanPhone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

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
                                        final newCust = Customer(
                                          id: (res['id'] ?? 0) as int,
                                          name: name,
                                          mobile: '+91 $cleanPhone',
                                          address: addressCtrl.text.trim(),
                                          notes: notesCtrl.text.trim(),
                                        );

                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                        }
                                        _loadCustomers();

                                        if (mounted) {
                                          if (widget.isSelectMode) {
                                            widget.onSelectCustomer?.call(newCust);
                                            Navigator.pop(context, newCust);
                                          }
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Customer "$name" saved!'),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      } catch (err) {
                                        setModalState(() => isSaving = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
                                          );
                                        }
                                      }
                                    },
                              child: isSaving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(
                                      'Save Customer',
                                      style: TextStyle(
                                        color: canSave ? const Color(0xFF0F172A) : Colors.grey.shade400,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 2. SAVE & NEW ORDER (Directly create order for this new customer)
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add_shopping_cart, size: 16, color: Colors.white),
                              label: const Text(
                                'Save & New Order',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canSave ? const Color(0xFF2563EB) : Colors.grey.shade400,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: canSave ? 2 : 0,
                              ),
                              onPressed: !canSave
                                  ? null
                                  : () async {
                                      final name = nameCtrl.text.trim();
                                      final cleanPhone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

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
                                        final newCust = Customer(
                                          id: (res['id'] ?? 0) as int,
                                          name: name,
                                          mobile: '+91 $cleanPhone',
                                          address: addressCtrl.text.trim(),
                                          notes: notesCtrl.text.trim(),
                                        );

                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                        }
                                        _loadCustomers();

                                        if (mounted) {
                                          if (widget.isSelectMode) {
                                            widget.onSelectCustomer?.call(newCust);
                                            Navigator.pop(context, newCust);
                                          } else {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => NewOrderScreen(preSelectedCustomer: newCust),
                                              ),
                                            );
                                          }
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Customer "$name" save ho gaya! Naya order shuru karein.'),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      } catch (err) {
                                        setModalState(() => isSaving = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
                                          );
                                        }
                                      }
                                    },
                            ),
                          ),
                        ),
                      ],
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

  void _showEditCustomerDialog(Customer c) {
    final nameCtrl = TextEditingController(text: c.name);
    String rawMobile = c.mobile.replaceAll('+91', '').replaceAll(' ', '').trim();
    rawMobile = rawMobile.replaceAll(RegExp(r'\D'), '');
    final mobileCtrl = TextEditingController(text: rawMobile);
    final addressCtrl = TextEditingController(text: c.address);
    final notesCtrl = TextEditingController(text: c.notes);
    String? phoneError;
    String? phoneHelper = '10 ank ka mobile number dalein';
    bool isPhoneValid = rawMobile.length == 10 && ['6', '7', '8', '9'].contains(rawMobile[0]);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void validatePhone(String val) {
              final clean = val.replaceAll(RegExp(r'\D'), '');
              if (clean.isEmpty) {
                phoneError = null;
                phoneHelper = '10 ank ka mobile number dalein';
                isPhoneValid = false;
              } else if (!['6', '7', '8', '9'].contains(clean[0])) {
                phoneError = 'Mobile number 6, 7, 8 ya 9 se shuru hona chahiye';
                phoneHelper = null;
                isPhoneValid = false;
              } else if (clean.length < 10) {
                phoneError = null;
                phoneHelper = '${clean.length}/10 ank darj kiye (10 ank zaroori)';
                isPhoneValid = false;
              } else {
                // Exactly 10 digits starting with 6-9
                final match = _allCustomers.firstWhere(
                  (cust) => cust.id != c.id && cust.cleanMobile == clean,
                  orElse: () => Customer(id: 0, name: '', mobile: ''),
                );
                if (match.id != 0) {
                  phoneError = 'Yeh number pehle se "${match.name}" ke paas hai! Duplicate allow nahi hai.';
                  phoneHelper = null;
                  isPhoneValid = false;
                } else {
                  phoneError = null;
                  phoneHelper = 'Sahi mobile number ✓';
                  isPhoneValid = true;
                }
              }
              setModalState(() {});
            }

            final canSave = !isSaving && isPhoneValid && nameCtrl.text.trim().isNotEmpty && phoneError == null;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Customer',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A)),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const Divider(height: 20),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
                    ],
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Customer Name *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: mobileCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: validatePhone,
                    decoration: InputDecoration(
                      prefixText: '+91 ',
                      prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 16),
                      labelText: 'Mobile Number *',
                      errorText: phoneError,
                      errorMaxLines: 2,
                      helperText: phoneError == null ? phoneHelper : null,
                      helperStyle: TextStyle(
                        color: isPhoneValid ? Colors.green.shade700 : Colors.grey.shade600,
                        fontWeight: isPhoneValid ? FontWeight.bold : FontWeight.normal,
                      ),
                      suffixIcon: isPhoneValid
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : (phoneError != null
                              ? const Icon(Icons.error_outline, color: Colors.red)
                              : Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                                  child: Text(
                                    '${mobileCtrl.text.replaceAll(RegExp(r"\D"), "").length}/10',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                  ),
                                )),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressCtrl,
                    decoration: InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSave ? const Color(0xFF0F172A) : Colors.grey.shade400,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: !canSave
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final cleanMobile = mobileCtrl.text.replaceAll(RegExp(r'\D'), '');
                              if (name.isEmpty || cleanMobile.length != 10) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Kripya naam aur 10-digit mobile number bharein.'), backgroundColor: Colors.orange),
                                );
                                return;
                              }

                              setModalState(() => isSaving = true);
                              try {
                                await ApiService.updateCustomer(
                                  id: c.id,
                                  name: name,
                                  mobile: '+91 $cleanMobile',
                                  address: addressCtrl.text.trim(),
                                  notes: notesCtrl.text.trim(),
                                );
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                }
                                _loadCustomers();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Customer details updated!'), backgroundColor: Colors.green),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Update fail: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            },
                      child: isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Changes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
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
        heroTag: 'customers_add_fab',
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
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.12),
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
                                onTap: () {
                                  if (widget.onSelectCustomer != null) {
                                    widget.onSelectCustomer!(c);
                                  } else if (widget.isSelectMode) {
                                    Navigator.pop(context, c);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CustomerDetailsScreen(customerId: c.id),
                                      ),
                                    );
                                  }
                                },
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.08),
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
                                trailing: (widget.onSelectCustomer != null || widget.isSelectMode)
                                    ? const Icon(Icons.check_circle_outline, color: Color(0xFF0F172A))
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blueGrey),
                                            tooltip: 'Edit Customer',
                                            onPressed: () => _showEditCustomerDialog(c),
                                          ),
                                          const Icon(Icons.chevron_right, color: Colors.grey),
                                        ],
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
}
