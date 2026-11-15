import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/device_quota.dart';
import '../../domain/models/quota_config.dart';

/// Persists global and per-device hotspot data quotas.
class QuotaService {
  static const String _globalQuotaKey = 'global_quota_v1';
  static const String _deviceQuotasKey = 'device_quotas_v1';

  Future<QuotaConfig> loadGlobalQuota() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_globalQuotaKey);
    if (raw == null || raw.isEmpty) {
      return QuotaConfig.defaults;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        if (decoded is Map) {
          return QuotaConfig.fromJson(Map<String, dynamic>.from(decoded));
        }
        return QuotaConfig.defaults;
      }
      return QuotaConfig.fromJson(decoded);
    } catch (_) {
      return QuotaConfig.defaults;
    }
  }

  Future<QuotaConfig> saveGlobalQuota(QuotaConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalQuotaKey, jsonEncode(config.toJson()));
    return config;
  }

  Future<Map<String, DeviceQuota>> loadDeviceQuotas() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceQuotasKey);
    if (raw == null || raw.isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, DeviceQuota>{};
      for (final entry in decoded.entries) {
        final key = entry.key?.toString();
        final val = entry.value;
        if (key != null && val is Map) {
          result[key] = DeviceQuota.fromJson(Map<String, dynamic>.from(val));
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, DeviceQuota>> saveDeviceQuota(DeviceQuota quota) async {
    final current = Map<String, DeviceQuota>.from(await loadDeviceQuotas());
    current[quota.deviceId] = quota;
    await _persistDeviceQuotas(current);
    return current;
  }

  Future<Map<String, DeviceQuota>> setDeviceBlocked(
    String deviceId,
    bool isBlocked,
  ) async {
    final current = Map<String, DeviceQuota>.from(await loadDeviceQuotas());
    final existing = current[deviceId] ?? DeviceQuota(deviceId: deviceId);
    current[deviceId] = existing.copyWith(isBlocked: isBlocked);
    await _persistDeviceQuotas(current);
    return current;
  }

  Future<Map<String, DeviceQuota>> removeDeviceQuota(String deviceId) async {
    final current = Map<String, DeviceQuota>.from(await loadDeviceQuotas());
    current.remove(deviceId);
    await _persistDeviceQuotas(current);
    return current;
  }

  Future<void> _persistDeviceQuotas(Map<String, DeviceQuota> quotas) async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final entry in quotas.entries) {
      map[entry.key] = entry.value.toJson();
    }
    await prefs.setString(_deviceQuotasKey, jsonEncode(map));
  }
}
