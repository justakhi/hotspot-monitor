/// Describes the OS permissions, root availability, and active hotspot interface.
class CapabilityState {
  const CapabilityState({
    required this.usageAccessGranted,
    required this.rootBinaryPresent,
    required this.rootGranted,
    required this.nativeProbeAvailable,
    required this.hotspotActive,
    required this.hotspotInterface,
    required this.gatewayIp,
    required this.prefixLength,
    required this.tetherType,
  });

  factory CapabilityState.fromMap(Map<Object?, Object?> map) {
    return CapabilityState(
      usageAccessGranted: map['usageAccessGranted'] == true,
      rootBinaryPresent: map['rootBinaryPresent'] == true,
      rootGranted: map['rootGranted'] == true,
      nativeProbeAvailable: map['nativeProbeAvailable'] == true,
      hotspotActive: map['hotspotActive'] == true,
      hotspotInterface: map['hotspotInterface'] as String?,
      gatewayIp: map['gatewayIp'] as String?,
      prefixLength: (map['prefixLength'] as num?)?.toInt() ?? 24,
      tetherType: (map['tetherType'] as String?) ?? 'none',
    );
  }

  static const CapabilityState initial = CapabilityState(
    usageAccessGranted: false,
    rootBinaryPresent: false,
    rootGranted: false,
    nativeProbeAvailable: false,
    hotspotActive: false,
    hotspotInterface: null,
    gatewayIp: null,
    prefixLength: 24,
    tetherType: 'none',
  );

  final bool usageAccessGranted;
  final bool rootBinaryPresent;
  final bool rootGranted;
  final bool nativeProbeAvailable;
  final bool hotspotActive;
  final String? hotspotInterface;
  final String? gatewayIp;
  final int prefixLength;
  final String tetherType;
}
