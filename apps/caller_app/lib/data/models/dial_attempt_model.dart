class DialAttemptModel {
  final String id;
  final String leadId;
  final String callerId;
  final String? deviceId;
  final DateTime dialedAt;
  final String status;

  DialAttemptModel({
    required this.id,
    required this.leadId,
    required this.callerId,
    this.deviceId,
    required this.dialedAt,
    required this.status,
  });

  factory DialAttemptModel.fromJson(Map<String, dynamic> json) {
    return DialAttemptModel(
      id: json['id'] as String,
      leadId: json['lead_id'] as String,
      callerId: json['caller_id'] as String,
      deviceId: json['device_id'] as String?,
      dialedAt: DateTime.parse(json['dialed_at'] as String),
      status: json['status'] as String? ?? 'open',
    );
  }

  bool get isOpen => status == 'open';
}
