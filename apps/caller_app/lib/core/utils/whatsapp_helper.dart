import 'package:url_launcher/url_launcher.dart';

class WhatsAppHelper {
  /// Opens WhatsApp with a pre-filled professional corporate follow-up message
  static Future<bool> openFollowUpChat({
    required String phoneE164,
    required String leadName,
    required String callerName,
    String? customMessage,
  }) async {
    // Strip non-digits for WhatsApp api
    final cleanPhone = phoneE164.replaceAll(RegExp(r'[^0-9]'), '');

    final message = customMessage ??
        'Hi ${leadName.trim()}, this is ${callerName.trim()} from Orvyq Media. '
        'Thank you for speaking with me today! Following up on our conversation—'
        'feel free to save this number or reply here if you have any questions. Have a great day!';

    final uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
