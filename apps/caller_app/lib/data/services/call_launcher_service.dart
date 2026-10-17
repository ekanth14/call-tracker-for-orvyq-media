import 'package:url_launcher/url_launcher.dart';

class CallLauncherService {
  /// Opens the native Android dialer pre-populated with the target phone number.
  /// Uses tel:<number> scheme.
  Future<bool> launchDialer(String phoneE164) async {
    final cleanNumber = phoneE164.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri(scheme: 'tel', path: cleanNumber);

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
