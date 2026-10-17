class UserProfileModel {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? mobileE164;
  final bool isActive;

  UserProfileModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.mobileE164,
    this.isActive = true,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      role: json['role'] as String? ?? 'caller',
      mobileE164: json['mobile_e164'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  bool get isCaller => role == 'caller';
  bool get isOwner => role == 'owner';
}
