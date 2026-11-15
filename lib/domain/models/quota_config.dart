/// Global hotspot data quota configuration.
class QuotaConfig {
  final bool enabled;
  final int limitBytes;
  final int warningPercent;

  const QuotaConfig({
    this.enabled = false,
    this.limitBytes = 1024 * 1024 * 1024, // 1 GB
    this.warningPercent = 80,
  });

  static const QuotaConfig defaults = QuotaConfig();

  QuotaConfig copyWith({
    bool? enabled,
    int? limitBytes,
    int? warningPercent,
  }) {
    return QuotaConfig(
      enabled: enabled ?? this.enabled,
      limitBytes: limitBytes ?? this.limitBytes,
      warningPercent: warningPercent ?? this.warningPercent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'limitBytes': limitBytes,
      'warningPercent': warningPercent,
    };
  }

  factory QuotaConfig.fromJson(Map<String, dynamic> json) {
    return QuotaConfig(
      enabled: json['enabled'] as bool? ?? false,
      limitBytes: (json['limitBytes'] as num?)?.toInt() ?? 1024 * 1024 * 1024,
      warningPercent: (json['warningPercent'] as num?)?.toInt() ?? 80,
    );
  }
}
