import 'package:url_launcher/url_launcher.dart';
import '../services/local_storage_service.dart';

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

    // If it starts with duplicate 9191 (e.g. 91919876543210), strip the first 91
    if (digits.startsWith('9191') && digits.length >= 14) {
      return digits.substring(2);
    }

    // If it's more than 10 digits and starts with 91
    if (digits.startsWith('91')) {
      return digits;
    }

    // Fallback: if 10 digits or less, prepend 91
    return digits.length <= 10 ? '91$digits' : digits;
  }

  /// Launches WhatsApp safely with proper encoding
  static Future<bool> openWhatsApp(String phone, [String message = '']) async {
    final cleanPhone = formatWhatsAppPhone(phone);
    if (cleanPhone.isEmpty) return false;

    final encodedMsg = Uri.encodeComponent(message);
    final urlStr = message.isNotEmpty
        ? 'https://wa.me/$cleanPhone?text=$encodedMsg'
        : 'https://wa.me/$cleanPhone';
    final url = Uri.parse(urlStr);

    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Fallback
      final fallbackUrlStr = message.isNotEmpty
          ? 'whatsapp://send?phone=$cleanPhone&text=$encodedMsg'
          : 'whatsapp://send?phone=$cleanPhone';
      final fallbackUrl = Uri.parse(fallbackUrlStr);
      if (await canLaunchUrl(fallbackUrl)) {
        return await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      }
      return false;
    }
  }

  /// Calls customer phone via dialer
  static Future<bool> callCustomer(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) return false;
    final url = Uri.parse('tel:$clean');
    try {
      return await launchUrl(url);
    } catch (_) {
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
        return await openWhatsApp(phone, text);
      }

      // If parsing didn't find phone, launch directly
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }

  /// Formats a customized message template from LocalStorageService
  static Future<String> formatTemplate(String templateKey, Map<String, String> values) async {
    final templates = await LocalStorageService.getMessageTemplates();
    String tmpl = templates[templateKey] ?? (LocalStorageService.defaultMessageTemplates[templateKey] ?? '');
    values.forEach((k, v) {
      tmpl = tmpl.replaceAll('{$k}', v);
    });
    return tmpl;
  }
}
