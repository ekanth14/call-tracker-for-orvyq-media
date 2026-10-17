import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile_model.dart';
import '../services/storage_service.dart';

class AuthRepository {
  final SupabaseClient _supabase;
  final StorageService _storageService;

  AuthRepository(this._supabase, this._storageService);

  User? get currentUser => _supabase.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<UserProfileModel> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Authentication failed. User is null.');
    }

    // Fetch profile
    final profile = await getUserProfile(user.id);
    if (!profile.isActive) {
      await _supabase.auth.signOut();
      throw Exception('Account is inactive. Please contact the owner.');
    }

    // Register or update device
    await _registerDevice(user.id);

    return profile;
  }

  Future<UserProfileModel> getUserProfile(String userId) async {
    final data = await _supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();

    return UserProfileModel.fromJson(data);
  }

  Future<void> _registerDevice(String userId) async {
    try {
      final deviceId = _storageService.getOrCreateDeviceId();
      await _supabase.from('devices').upsert({
        'id': deviceId,
        'profile_id': userId,
        'device_label': 'Android Phone',
        'app_version': '1.0.0',
        'last_sync_at': DateTime.now().toUtc().toIso8601String(),
        'permissions_ok': true,
      });
    } catch (_) {
      // Device registration failure should not block login
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  bool get hasAcceptedConsent => _storageService.hasAcceptedConsent;

  Future<void> acceptConsent() async {
    await _storageService.setConsentAccepted(true);
  }
}
