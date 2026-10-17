import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  static const String _keyConsentAccepted = 'has_accepted_privacy_consent';
  static const String _keyDeviceId = 'device_local_id';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  bool get hasAcceptedConsent => _prefs.getBool(_keyConsentAccepted) ?? false;

  Future<void> setConsentAccepted(bool value) async {
    await _prefs.setBool(_keyConsentAccepted, value);
  }

  String getOrCreateDeviceId() {
    String? id = _prefs.getString(_keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
