class DeviceCallLogModel {
  final String numberE164;
  final String rawNumber;
  final String callType; // 'outgoing', 'incoming', 'missed'
  final DateTime startedAt;
  final int durationSecs;
  final String? simSlot;
  final int timestampMillis;

  DeviceCallLogModel({
    required this.numberE164,
    required this.rawNumber,
    required this.callType,
    required this.startedAt,
    required this.durationSecs,
    this.simSlot,
    required this.timestampMillis,
  });

  factory DeviceCallLogModel.fromJson(Map<String, dynamic> json) {
    return DeviceCallLogModel(
      numberE164: json['number_e164'] as String,
      rawNumber: json['raw_number'] as String? ?? json['number_e164'] as String,
      callType: json['call_type'] as String? ?? 'outgoing',
      startedAt: DateTime.parse(json['started_at'] as String),
      durationSecs: (json['duration_secs'] as num?)?.toInt() ?? 0,
      simSlot: json['sim_slot'] as String?,
      timestampMillis: (json['timestamp_millis'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number_e164': numberE164,
      'raw_number': rawNumber,
      'call_type': callType,
      'started_at': startedAt.toIso8601String(),
      'duration_secs': durationSecs,
      'sim_slot': simSlot,
      'timestamp_millis': timestampMillis,
    };
  }

  bool get isOutgoing => callType.toLowerCase() == 'outgoing';
  bool get isConnected => durationSecs >= 10;
}
