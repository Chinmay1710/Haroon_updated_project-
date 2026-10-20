class Customer {
  final int id;
  final String name;
  final String mobile;
  final String address;
  final String notes;

  Customer({
    required this.id,
    required this.name,
    required this.mobile,
    this.address = '',
    this.notes = '',
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '',
      mobile: json['mobile']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }

  // Clean last 10 digits for duplicate comparison
  String get cleanMobile {
    final digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }
}
