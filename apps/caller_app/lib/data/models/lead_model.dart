class LeadModel {
  final String id;
  final String name;
  final String? company;
  final String? city;
  final String phoneE164;
  final String status;
  final int attemptCount;
  final String? notes;
  final DateTime? lastCallAt;
  final DateTime? nextFollowUpAt;
  final DateTime createdAt;

  LeadModel({
    required this.id,
    required this.name,
    this.company,
    this.city,
    required this.phoneE164,
    required this.status,
    this.attemptCount = 0,
    this.notes,
    this.lastCallAt,
    this.nextFollowUpAt,
    required this.createdAt,
  });

  factory LeadModel.fromJson(Map<String, dynamic> json) {
    return LeadModel(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim() ?? 'Unnamed Lead',
      company: json['company'] as String?,
      city: json['city'] as String?,
      phoneE164: json['phone_e164'] as String? ?? '',
      status: json['status'] as String? ?? 'assigned',
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String?,
      lastCallAt: json['last_call_at'] != null
          ? DateTime.tryParse(json['last_call_at'] as String)
          : null,
      nextFollowUpAt: json['next_follow_up_at'] != null
          ? DateTime.tryParse(json['next_follow_up_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'company': company,
      'city': city,
      'phone_e164': phoneE164,
      'status': status,
      'attempt_count': attemptCount,
      'notes': notes,
      'last_call_at': lastCallAt?.toIso8601String(),
      'next_follow_up_at': nextFollowUpAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isFollowUp => status == 'follow_up' || nextFollowUpAt != null;
  bool get isNewOrAssigned => status == 'new' || status == 'assigned';
}
