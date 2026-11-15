/// Describes the OS permissions, root availability, and active hotspot and upstream network interface.
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
    this.upstreamConnected = false,
    this.upstreamType = 'none',
    this.upstreamInterface,
    this.upstreamCarrier,
    this.upstreamDetails = 'No Internet Connection',
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
      upstreamConnected: map['upstreamConnected'] == true,
      upstreamType: (map['upstreamType'] as String?) ?? 'none',
      upstreamInterface: map['upstreamInterface'] as String?,
      upstreamCarrier: map['upstreamCarrier'] as String?,
      upstreamDetails:
          (map['upstreamDetails'] as String?) ?? 'No Internet Connection',
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
    upstreamConnected: false,
    upstreamType: 'none',
    upstreamInterface: null,
    upstreamCarrier: null,
    upstreamDetails: 'No Internet Connection',
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
  final bool upstreamConnected;
  final String upstreamType;
  final String? upstreamInterface;
  final String? upstreamCarrier;
  final String upstreamDetails;
}
