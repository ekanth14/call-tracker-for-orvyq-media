import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../view_models/auth_view_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _email;
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _email = user.email;

    try {
      final data = await supabase
          .from('profiles')
          .select('full_name, mobile_e164, role')
          .eq('id', user.id)
          .single();

      if (mounted) {
        _nameController.text = data['full_name'] ?? '';
        _phoneController.text = data['mobile_e164'] ?? '';
        _role = data['role'] ?? 'caller';
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Update Profile table
      await supabase.from('profiles').update({
        'full_name': _nameController.text.trim(),
        'mobile_e164': _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
      }).eq('id', user.id);

      // 2. Update Password if provided
      final newPass = _newPasswordController.text.trim();
      if (newPass.isNotEmpty) {
        await supabase.auth.updateUser(UserAttributes(password: newPass));
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Avatar & Header
                    Center(
                      child: Column(
                        children: [
                          Container(
                            height: 76,
                            width: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              border: Border.all(color: AppTheme.primary, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                _nameController.text.isNotEmpty
                                    ? _nameController.text.substring(0, 1).toUpperCase()
                                    : 'C',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _nameController.text.isNotEmpty
                                ? _nameController.text
                                : 'Orvyq Employee',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              (_role ?? 'caller').toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Section: Personal Information
                    const Text(
                      'Personal Information',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Full Name
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    // Email (Read-only)
                    TextFormField(
                      initialValue: _email ?? '',
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Email Address (Managed by Admin)',
                        prefixIcon: Icon(Icons.email_outlined, size: 20),
                        filled: true,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Mobile SIM
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile SIM Number (+91...)',
                        prefixIcon: Icon(Icons.phone_android_outlined, size: 20),
                        hintText: '+919876543210',
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Section: Security / Password
                    const Text(
                      'Security & Password',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Leave blank if you do not wish to change your password',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),

                    // New Password
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: Icon(Icons.lock_outline, size: 20),
                      ),
                      validator: (val) {
                        if (val != null && val.isNotEmpty && val.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    // Confirm Password
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: Icon(Icons.lock_reset_outlined, size: 20),
                      ),
                      validator: (val) {
                        if (_newPasswordController.text.isNotEmpty &&
                            val != _newPasswordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save Changes'),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Logout Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout, size: 18, color: AppTheme.danger),
                        label: const Text(
                          'Sign Out',
                          style: TextStyle(color: AppTheme.danger),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.3)),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          final authVm = Provider.of<AuthViewModel>(context, listen: false);
                          await authVm.signOut();
                        },
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}
