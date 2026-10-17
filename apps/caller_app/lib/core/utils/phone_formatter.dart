/// Utility for formatting and displaying phone numbers cleanly
class PhoneFormatter {
  PhoneFormatter._();

  /// Formats an E.164 phone string (e.g. "+918971027214") into human-friendly format:
  /// "+91 89710 27214"
  static String formatE164(String? phone) {
    if (phone == null || phone.isEmpty) return 'No Phone';
    final digits = phone.replaceAll(RegExp(r'\D'), '');

    if (phone.startsWith('+91') && digits.length == 12) {
      // +91 XXXXX XXXXX
      final local = digits.substring(2);
      return '+91 ${local.substring(0, 5)} ${local.substring(5)}';
    } else if (digits.length == 10) {
      return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
    }

    return phone;
  }

  /// Partially masks a phone number for UI display if needed:
  /// "+91 897•• ••214"
  static String maskPhone(String? phone) {
    if (phone == null || phone.isEmpty) return 'No Phone';
    final formatted = formatE164(phone);
    if (formatted.length >= 12) {
      return formatted.replaceRange(7, formatted.length - 3, '•• ••');
    }
    return formatted;
  }
}
