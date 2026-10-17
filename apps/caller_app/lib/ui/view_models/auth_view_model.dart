import 'package:flutter/foundation.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/repositories/auth_repository.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  AuthViewModel(this._authRepository) {
    _checkInitialAuth();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  UserProfileModel? _profile;
  UserProfileModel? get profile => _profile;

  bool get isAuthenticated => _authRepository.isAuthenticated;
  bool get hasAcceptedConsent => _authRepository.hasAcceptedConsent;

  Future<void> _checkInitialAuth() async {
    final user = _authRepository.currentUser;
    if (user != null) {
      try {
        _profile = await _authRepository.getUserProfile(user.id);
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await _authRepository.signIn(
        email: email,
        password: password,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> acceptPrivacyConsent() async {
    await _authRepository.acceptConsent();
    notifyListeners();
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    await _authRepository.signOut();
    _profile = null;
    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
