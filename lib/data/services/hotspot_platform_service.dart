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
  Future<bool> setDeviceBlocked({
    required String ip,
    String? mac,
    required bool blocked,
  });
  Future<List<String>> getBlockedIps();
  Future<bool> openHotspotSettings();
  Future<bool> toggleHotspot();
  Future<bool> isBatteryOptimizationIgnored();
  Future<bool> requestIgnoreBatteryOptimization();
  Future<bool> setBackgroundServiceEnabled(bool enabled);
  Future<bool> isBackgroundServiceEnabled();
  Future<bool> shareExport({
    required String filename,
    required String content,
    required String title,
    String mimeType = 'text/csv',
  });
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

  @override
  Future<bool> setDeviceBlocked({
    required String ip,
    String? mac,
    required bool blocked,
  }) async {
    final res = await _control.invokeMethod<bool>('setDeviceBlocked', {
      'ip': ip,
      'mac': mac,
      'blocked': blocked,
    });
    return res ?? false;
  }

  @override
  Future<List<String>> getBlockedIps() async {
    final res = await _control.invokeListMethod<String>('getBlockedIps');
    return res ?? const [];
  }

  @override
  Future<bool> openHotspotSettings() async {
    final res = await _control.invokeMethod<bool>('openHotspotSettings');
    return res ?? false;
  }

  @override
  Future<bool> toggleHotspot() async {
    final res = await _control.invokeMethod<bool>('toggleHotspot');
    return res ?? false;
  }

  @override
  Future<bool> isBatteryOptimizationIgnored() async {
    final res = await _control.invokeMethod<bool>('isBatteryOptimizationIgnored');
    return res ?? false;
  }

  @override
  Future<bool> requestIgnoreBatteryOptimization() async {
    final res = await _control.invokeMethod<bool>(
      'requestIgnoreBatteryOptimization',
    );
    return res ?? false;
  }

  @override
  Future<bool> setBackgroundServiceEnabled(bool enabled) async {
    final res = await _control.invokeMethod<bool>(
      'setBackgroundServiceEnabled',
      {'enabled': enabled},
    );
    return res ?? false;
  }

  @override
  Future<bool> isBackgroundServiceEnabled() async {
    final res = await _control.invokeMethod<bool>('isBackgroundServiceEnabled');
    return res ?? false;
  }

  @override
  Future<bool> shareExport({
    required String filename,
    required String content,
    required String title,
    String mimeType = 'text/csv',
  }) async {
    final res = await _control.invokeMethod<bool>(
      'shareExport',
      {
        'filename': filename,
        'content': content,
        'title': title,
        'mimeType': mimeType,
      },
    );
    return res ?? false;
  }
}
