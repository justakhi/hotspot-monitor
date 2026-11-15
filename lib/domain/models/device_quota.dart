/// Per-device data quota and internet blocking state.
class DeviceQuota {
  final String deviceId;
  final int? limitBytes; // null means no limit set
  final bool autoBlockExceeded;
  final bool isBlocked;

  const DeviceQuota({
    required this.deviceId,
    this.limitBytes,
    this.autoBlockExceeded = false,
    this.isBlocked = false,
  });

  DeviceQuota copyWith({
    String? deviceId,
    int? limitBytes,
    bool clearLimit = false,
    bool? autoBlockExceeded,
    bool? isBlocked,
  }) {
    return DeviceQuota(
      deviceId: deviceId ?? this.deviceId,
      limitBytes: clearLimit ? null : (limitBytes ?? this.limitBytes),
      autoBlockExceeded: autoBlockExceeded ?? this.autoBlockExceeded,
      isBlocked: isBlocked ?? this.isBlocked,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'limitBytes': limitBytes,
      'autoBlockExceeded': autoBlockExceeded,
      'isBlocked': isBlocked,
    };
  }

  factory DeviceQuota.fromJson(Map<String, dynamic> json) {
    return DeviceQuota(
      deviceId: json['deviceId'] as String? ?? '',
      limitBytes: (json['limitBytes'] as num?)?.toInt(),
      autoBlockExceeded: json['autoBlockExceeded'] as bool? ?? false,
      isBlocked: json['isBlocked'] as bool? ?? false,
    );
  }
}
