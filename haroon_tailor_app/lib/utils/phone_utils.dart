import 'package:url_launcher/url_launcher.dart';

class PhoneUtils {
  /// Cleans any raw phone string to a strict 12-digit Indian format (e.g. 919876543210)
  /// Prevents any 9191 duplication bug.
  static String formatWhatsAppPhone(String rawPhone) {
    var digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    // If starts with 91 and has 12 digits (e.g. 919876543210), it's already complete!
    if (digits.startsWith('91') && digits.length == 12) {
      return digits;
    }

    // If starts with 0 and has 11 digits (e.g. 09876543210), drop leading 0 and add 91
    if (digits.startsWith('0') && digits.length == 11) {
      return '91${digits.substring(1)}';
    }

    // If it's a 10-digit mobile number, prepend 91
    if (digits.length == 10) {
      return '91$digits';
    }

    // If it's more than 10 digits and starts with 91
    if (digits.startsWith('91')) {
      return digits;
    }

    // Fallback: if 10 digits or less, prepend 91
    return digits.length <= 10 ? '91$digits' : digits;
  }

  /// Launches WhatsApp safely with proper encoding
  static Future<bool> openWhatsApp({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = formatWhatsAppPhone(phone);
    if (cleanPhone.isEmpty) return false;

    final encodedMsg = Uri.encodeComponent(message);
    final url = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMsg');

    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Fallback
      final fallbackUrl = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedMsg');
      if (await canLaunchUrl(fallbackUrl)) {
        return await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      }
      return false;
    }
  }

  /// Parses a backend-generated whatsapp:// or https://wa.me URL and fixes duplicate 91
  static Future<bool> openBackendWhatsAppUrl(String urlStr) async {
    if (urlStr.isEmpty) return false;

    try {
      final uri = Uri.parse(urlStr);
      String phone = '';
      String text = '';

      if (uri.scheme == 'whatsapp') {
        phone = uri.queryParameters['phone'] ?? '';
        text = uri.queryParameters['text'] ?? '';
      } else if (uri.host.contains('wa.me')) {
        phone = uri.path.replaceAll('/', '');
        text = uri.queryParameters['text'] ?? '';
      }

      if (phone.isNotEmpty) {
        return await openWhatsApp(phone: phone, message: text);
      }

      // If parsing didn't find phone, launch directly
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }
}
