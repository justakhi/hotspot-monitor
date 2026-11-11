import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists user-assigned friendly labels for connected devices by ID/MAC.
class DeviceAliasService {
  static const String _storageKey = 'device_aliases_v1';

  Future<Map<String, String>> loadAliases() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key?.toString();
        final value = entry.value?.toString();
        if (key != null && value != null && value.trim().isNotEmpty) {
          result[key] = value.trim();
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, String>> saveAlias(String deviceId, String alias) async {
    final current = Map<String, String>.from(await loadAliases());
    final trimmed = alias.trim();
    if (trimmed.isEmpty) {
      current.remove(deviceId);
    } else {
      current[deviceId] = trimmed;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(current));
    return current;
  }
}
