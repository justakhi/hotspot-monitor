import 'package:flutter/services.dart';

import '../../domain/models/capability_state.dart';

/// Contract for communicating with the Android native hotspot monitor engine.
abstract class HotspotPlatformService {
  Stream<Map<Object?, Object?>> get telemetryStream;
  Future<CapabilityState> getCapabilities();
  Future<void> openUsageAccessSettings();
  Future<CapabilityState> requestRootAccess();
  Future<CapabilityState> setRootModeEnabled(bool enabled);
  Future<void> resetSession();
  Future<Map<Object?, Object?>> scanNow();
  Future<bool> openUrl(String url);
}

/// Platform channel implementation backed by `MainActivity.kt`.
class MethodChannelHotspotPlatformService implements HotspotPlatformService {
  static const MethodChannel _control = MethodChannel(
    'com.justakhi.hotspot_monitor/control',
  );
  static const EventChannel _telemetry = EventChannel(
    'com.justakhi.hotspot_monitor/telemetry',
  );

  Stream<Map<Object?, Object?>>? _cachedStream;

  @override
  Stream<Map<Object?, Object?>> get telemetryStream {
    return _cachedStream ??= _telemetry
        .receiveBroadcastStream()
        .where((event) => event is Map<Object?, Object?>)
        .cast<Map<Object?, Object?>>()
        .asBroadcastStream();
  }

  @override
  Future<CapabilityState> getCapabilities() async {
    final res = await _control.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
    );
    return res == null ? CapabilityState.initial : CapabilityState.fromMap(res);
  }

  @override
  Future<void> openUsageAccessSettings() async {
    await _control.invokeMethod<bool>('openUsageAccessSettings');
  }

  @override
  Future<CapabilityState> requestRootAccess() async {
    final res = await _control.invokeMapMethod<Object?, Object?>(
      'requestRootAccess',
    );
    return res == null ? CapabilityState.initial : CapabilityState.fromMap(res);
  }

  @override
  Future<CapabilityState> setRootModeEnabled(bool enabled) async {
    final res = await _control.invokeMapMethod<Object?, Object?>(
      'setRootModeEnabled',
      {'enabled': enabled},
    );
    return res == null ? CapabilityState.initial : CapabilityState.fromMap(res);
  }

  @override
  Future<void> resetSession() async {
    await _control.invokeMethod<bool>('resetSession');
  }

  @override
  Future<Map<Object?, Object?>> scanNow() async {
    final res = await _control.invokeMapMethod<Object?, Object?>('scanNow');
    return res ?? const {};
  }

  @override
  Future<bool> openUrl(String url) async {
    final opened = await _control.invokeMethod<bool>('openUrl', {'url': url});
    return opened ?? false;
  }
}
