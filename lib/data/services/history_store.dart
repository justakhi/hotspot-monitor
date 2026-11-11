import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/connected_device.dart';
import '../../domain/models/history_report.dart';
import '../../domain/models/service_usage.dart';

class UsageDeltaRecord {
  const UsageDeltaRecord({
    required this.deviceId,
    required this.serviceId,
    required this.displayName,
    required this.category,
    required this.topDomains,
    required this.downloadDelta,
    required this.uploadDelta,
    this.endpoints = const [],
  });

  final String deviceId;
  final String serviceId;
  final String displayName;
  final String category;
  final List<String> topDomains;
  final int downloadDelta;
  final int uploadDelta;
  final List<EndpointUsage> endpoints;
}

abstract class HistoryStore {
  Future<void> initialize();
  Future<void> recordBatch({
    required int timestampMs,
    required List<ConnectedDevice> devices,
    required List<UsageDeltaRecord> deltas,
  });
  Future<UsageReport> queryReport({
    required HistoryRange range,
    required Map<String, String> aliases,
    String? deviceId,
    DateTime? now,
  });
  Future<DeviceHistorySummary?> queryDeviceSummary(
    String deviceId, {
    required Map<String, String> aliases,
  });
  Future<List<DeviceHistorySummary>> queryAllDevices({
    required Map<String, String> aliases,
  });
  Future<void> clearAll();
  Future<void> close();
}

/// Computes local hour bucket start timestamp in milliseconds.
int localHourBucketStartMs(DateTime dt) {
  return DateTime(dt.year, dt.month, dt.day, dt.hour).millisecondsSinceEpoch;
}

List<EndpointUsage> _mergeEndpointLists(
  List<EndpointUsage> existing,
  List<EndpointUsage> incoming, {
  int limit = 15,
}) {
  if (existing.isEmpty && incoming.isEmpty) return const [];
  final map = <String, EndpointUsage>{};
  for (final ep in [...existing, ...incoming]) {
    if (ep.endpoint.isEmpty) continue;
    final prev = map[ep.endpoint];
    if (prev == null) {
      map[ep.endpoint] = ep;
    } else {
      map[ep.endpoint] = EndpointUsage(
        endpoint: ep.endpoint,
        downloadBytes: prev.downloadBytes + ep.downloadBytes,
        uploadBytes: prev.uploadBytes + ep.uploadBytes,
        lastActiveMs: ep.lastActiveMs > prev.lastActiveMs
            ? ep.lastActiveMs
            : prev.lastActiveMs,
      );
    }
  }
  final merged = map.values.toList()
    ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
  return merged.take(limit).toList(growable: false);
}

List<EndpointUsage> _decodeEndpointsJson(String? rawJson) {
  if (rawJson == null || rawJson.length <= 2) return const [];
  try {
    final parsed = jsonDecode(rawJson);
    if (parsed is List) {
      return parsed
          .whereType<Map<Object?, Object?>>()
          .map(EndpointUsage.fromMap)
          .where((e) => e.endpoint.isNotEmpty)
          .toList(growable: false);
    }
  } catch (_) {}
  return const [];
}

int rangeStartMs(HistoryRange range, DateTime now) {
  switch (range) {
    case HistoryRange.hour:
      return localHourBucketStartMs(now);
    case HistoryRange.day:
      return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    case HistoryRange.month:
      return DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    case HistoryRange.year:
      return DateTime(now.year, 1, 1).millisecondsSinceEpoch;
    case HistoryRange.all:
      return 0;
  }
}

class SqliteHistoryStore implements HistoryStore {
  Database? _db;

  @override
  Future<void> initialize() async {
    if (_db != null) return;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'hotspot_history.db');
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE devices (
            device_id TEXT PRIMARY KEY,
            last_ip TEXT NOT NULL,
            mac TEXT,
            hostname TEXT,
            vendor TEXT NOT NULL,
            is_randomized_mac INTEGER NOT NULL DEFAULT 0,
            first_seen_ms INTEGER NOT NULL,
            last_seen_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE usage_buckets (
            bucket_hour INTEGER NOT NULL,
            device_id TEXT NOT NULL,
            service_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            category TEXT NOT NULL,
            top_domains TEXT NOT NULL DEFAULT '[]',
            endpoints_json TEXT NOT NULL DEFAULT '[]',
            download_bytes INTEGER NOT NULL DEFAULT 0,
            upload_bytes INTEGER NOT NULL DEFAULT 0,
            last_active_ms INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (bucket_hour, device_id, service_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_usage_device_hour ON usage_buckets(device_id, bucket_hour)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE usage_buckets ADD COLUMN endpoints_json TEXT NOT NULL DEFAULT '[]'",
          );
        }
      },
    );
  }

  @override
  Future<void> recordBatch({
    required int timestampMs,
    required List<ConnectedDevice> devices,
    required List<UsageDeltaRecord> deltas,
  }) async {
    final db = _db;
    if (db == null) return;
    if (devices.isEmpty && deltas.isEmpty) return;

    final bucketHour = localHourBucketStartMs(
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );

    await db.transaction((txn) async {
      for (final d in devices) {
        if (!d.isOnline && d.lastSeenMs <= 0 && d.totalBytes <= 0) {
          continue;
        }
        final effectiveLastSeen = d.isOnline
            ? timestampMs
            : d.lastSeenMs;
        await txn.rawInsert(
          '''
          INSERT INTO devices (
            device_id, last_ip, mac, hostname, vendor, is_randomized_mac,
            first_seen_ms, last_seen_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(device_id) DO UPDATE SET
            last_ip = excluded.last_ip,
            mac = COALESCE(excluded.mac, devices.mac),
            hostname = COALESCE(excluded.hostname, devices.hostname),
            vendor = CASE
              WHEN excluded.vendor != 'Unknown' AND excluded.vendor NOT LIKE 'Unknown (%' THEN excluded.vendor
              ELSE devices.vendor
            END,
            is_randomized_mac = excluded.is_randomized_mac,
            last_seen_ms = CASE
              WHEN ? = 1 THEN MAX(devices.last_seen_ms, excluded.last_seen_ms)
              ELSE devices.last_seen_ms
            END
          ''',
          [
            d.id,
            d.ip,
            d.mac,
            d.hostname,
            d.vendor,
            d.isRandomizedMac ? 1 : 0,
            timestampMs,
            effectiveLastSeen,
            d.isOnline ? 1 : 0,
          ],
        );
      }

      for (final delta in deltas) {
        if (delta.downloadDelta <= 0 && delta.uploadDelta <= 0) continue;
        if (delta.deviceId == '_hotspot_total_') {
          await txn.rawInsert(
            '''
            INSERT INTO devices (
              device_id, last_ip, mac, hostname, vendor, is_randomized_mac,
              first_seen_ms, last_seen_ms
            ) VALUES ('_hotspot_total_', 'All Devices', NULL, 'Hotspot Total', 'Non-Root Mode', 0, ?, ?)
            ON CONFLICT(device_id) DO UPDATE SET
              last_seen_ms = MAX(devices.last_seen_ms, excluded.last_seen_ms)
            ''',
            [timestampMs, timestampMs],
          );
        }
        var mergedEndpoints = delta.endpoints;
        if (delta.endpoints.isNotEmpty) {
          final existingRows = await txn.query(
            'usage_buckets',
            columns: ['endpoints_json'],
            where: 'bucket_hour = ? AND device_id = ? AND service_id = ?',
            whereArgs: [bucketHour, delta.deviceId, delta.serviceId],
            limit: 1,
          );
          if (existingRows.isNotEmpty) {
            final existingEndpoints = _decodeEndpointsJson(
              existingRows.first['endpoints_json'] as String?,
            );
            mergedEndpoints = _mergeEndpointLists(
              existingEndpoints,
              delta.endpoints,
            );
          }
        }
        await txn.rawInsert(
          '''
          INSERT INTO usage_buckets (
            bucket_hour, device_id, service_id, display_name, category,
            top_domains, endpoints_json, download_bytes, upload_bytes, last_active_ms
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(bucket_hour, device_id, service_id) DO UPDATE SET
            display_name = excluded.display_name,
            category = excluded.category,
            top_domains = CASE
              WHEN length(excluded.top_domains) > 2 THEN excluded.top_domains
              ELSE usage_buckets.top_domains
            END,
            endpoints_json = CASE
              WHEN length(excluded.endpoints_json) > 2 THEN excluded.endpoints_json
              ELSE usage_buckets.endpoints_json
            END,
            download_bytes = usage_buckets.download_bytes + excluded.download_bytes,
            upload_bytes = usage_buckets.upload_bytes + excluded.upload_bytes,
            last_active_ms = MAX(usage_buckets.last_active_ms, excluded.last_active_ms)
          ''',
          [
            bucketHour,
            delta.deviceId,
            delta.serviceId,
            delta.displayName,
            delta.category,
            jsonEncode(delta.topDomains.take(5).toList(growable: false)),
            jsonEncode(
              mergedEndpoints.take(15).map((e) => e.toJson()).toList(growable: false),
            ),
            delta.downloadDelta,
            delta.uploadDelta,
            timestampMs,
          ],
        );
      }
    });
  }

  @override
  Future<UsageReport> queryReport({
    required HistoryRange range,
    required Map<String, String> aliases,
    String? deviceId,
    DateTime? now,
  }) async {
    final db = _db;
    if (db == null) return UsageReport.empty;

    final refNow = now ?? DateTime.now();
    final minHour = rangeStartMs(range, refNow);

    final whereClause = StringBuffer('u.bucket_hour >= ?');
    final whereArgs = <Object?>[minHour];
    if (deviceId != null) {
      whereClause.write(' AND u.device_id = ?');
      whereArgs.add(deviceId);
    }

    final bucketRows = await db.rawQuery(
      '''
      SELECT u.bucket_hour,
             SUM(u.download_bytes) AS rx,
             SUM(u.upload_bytes) AS tx
      FROM usage_buckets u
      WHERE $whereClause
      GROUP BY u.bucket_hour
      ORDER BY u.bucket_hour ASC
      ''',
      whereArgs,
    );

    var totalRx = 0;
    var totalTx = 0;
    final rawHourPoints = <(int hourMs, int rx, int tx)>[];
    for (final row in bucketRows) {
      final h = (row['bucket_hour'] as num?)?.toInt() ?? 0;
      final rx = (row['rx'] as num?)?.toInt() ?? 0;
      final tx = (row['tx'] as num?)?.toInt() ?? 0;
      totalRx += rx;
      totalTx += tx;
      rawHourPoints.add((h, rx, tx));
    }

    final deviceServiceRows = await db.rawQuery(
      '''
      SELECT u.device_id,
             u.service_id,
             u.display_name,
             u.category,
             MAX(u.top_domains) AS top_domains,
             MAX(u.last_active_ms) AS last_active_ms,
             SUM(u.download_bytes) AS rx,
             SUM(u.upload_bytes) AS tx
      FROM usage_buckets u
      WHERE $whereClause
      GROUP BY u.device_id, u.service_id
      ORDER BY (SUM(u.download_bytes) + SUM(u.upload_bytes)) DESC
      ''',
      whereArgs,
    );

    final epRows = await db.rawQuery(
      '''
      SELECT u.device_id, u.service_id, u.endpoints_json
      FROM usage_buckets u
      WHERE $whereClause AND length(u.endpoints_json) > 2
      ''',
      whereArgs,
    );
    final devSvcEndpoints = <String, List<EndpointUsage>>{};
    final globalSvcEndpoints = <String, List<EndpointUsage>>{};
    for (final epRow in epRows) {
      final dId = (epRow['device_id'] as String?) ?? '';
      final sId = (epRow['service_id'] as String?) ?? '';
      final parsed = _decodeEndpointsJson(epRow['endpoints_json'] as String?);
      if (parsed.isEmpty) continue;
      final dsKey = '$dId|$sId';
      devSvcEndpoints[dsKey] = _mergeEndpointLists(
        devSvcEndpoints[dsKey] ?? const [],
        parsed,
      );
      globalSvcEndpoints[sId] = _mergeEndpointLists(
        globalSvcEndpoints[sId] ?? const [],
        parsed,
      );
    }

    final servicesByDevice = <String, List<ServiceUsage>>{};
    final globalAgg = <String, ({String name, String cat, Set<String> domains, int rx, int tx, int lastMs})>{};

    for (final row in deviceServiceRows) {
      final dId = (row['device_id'] as String?) ?? 'unknown';
      final sId = (row['service_id'] as String?) ?? 'unknown';
      final name = (row['display_name'] as String?) ?? 'Unknown';
      final cat = (row['category'] as String?) ?? 'Other';
      final rx = (row['rx'] as num?)?.toInt() ?? 0;
      final tx = (row['tx'] as num?)?.toInt() ?? 0;
      final lastMs = (row['last_active_ms'] as num?)?.toInt() ?? 0;

      final domainsJson = (row['top_domains'] as String?) ?? '[]';
      List<String> domains = const [];
      try {
        final parsed = jsonDecode(domainsJson);
        if (parsed is List) {
          domains = parsed.whereType<String>().toList(growable: false);
        }
      } catch (_) {}

      final dsEndpoints = devSvcEndpoints['$dId|$sId'] ?? const <EndpointUsage>[];
      servicesByDevice.putIfAbsent(dId, () => []).add(
        ServiceUsage(
          serviceId: sId,
          displayName: name,
          category: cat,
          downloadBytes: rx,
          uploadBytes: tx,
          topDomains: domains,
          lastActiveMs: lastMs,
          endpoints: dsEndpoints,
        ),
      );

      final prev = globalAgg[sId];
      final domSet = prev?.domains ?? <String>{};
      domSet.addAll(domains);
      globalAgg[sId] = (
        name: name,
        cat: cat,
        domains: domSet,
        rx: (prev?.rx ?? 0) + rx,
        tx: (prev?.tx ?? 0) + tx,
        lastMs: lastMs > (prev?.lastMs ?? 0) ? lastMs : (prev?.lastMs ?? 0),
      );
    }

    final services = globalAgg.entries
        .map(
          (e) => ServiceUsage(
            serviceId: e.key,
            displayName: e.value.name,
            category: e.value.cat,
            downloadBytes: e.value.rx,
            uploadBytes: e.value.tx,
            topDomains: e.value.domains.take(5).toList(growable: false),
            lastActiveMs: e.value.lastMs,
            endpoints: globalSvcEndpoints[e.key] ?? const [],
          ),
        )
        .toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    final deviceRows = await db.rawQuery(
      '''
      SELECT d.device_id,
             d.last_ip,
             d.mac,
             d.hostname,
             d.vendor,
             d.is_randomized_mac,
             d.first_seen_ms,
             d.last_seen_ms,
             SUM(u.download_bytes) AS rx,
             SUM(u.upload_bytes) AS tx
      FROM usage_buckets u
      LEFT JOIN devices d ON d.device_id = u.device_id
      WHERE $whereClause
      GROUP BY u.device_id
      ORDER BY (SUM(u.download_bytes) + SUM(u.upload_bytes)) DESC
      ''',
      whereArgs,
    );

    final devices = deviceRows
        .map((row) {
          final id = (row['device_id'] as String?) ?? 'unknown';
          return DeviceHistorySummary(
            deviceId: id,
            ip: (row['last_ip'] as String?) ?? id,
            mac: row['mac'] as String?,
            hostname: row['hostname'] as String?,
            vendor: (row['vendor'] as String?) ?? 'Unknown',
            isRandomizedMac: ((row['is_randomized_mac'] as num?)?.toInt() ?? 0) == 1,
            customAlias: aliases[id],
            downloadBytes: (row['rx'] as num?)?.toInt() ?? 0,
            uploadBytes: (row['tx'] as num?)?.toInt() ?? 0,
            firstSeenMs: (row['first_seen_ms'] as num?)?.toInt() ?? 0,
            lastSeenMs: (row['last_seen_ms'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);

    return UsageReport(
      range: range,
      totalDownloadBytes: totalRx,
      totalUploadBytes: totalTx,
      timeline: _aggregateTimeline(range, rawHourPoints, refNow),
      devices: devices,
      services: services,
      servicesByDevice: servicesByDevice.map(
        (k, v) => MapEntry(k, List<ServiceUsage>.unmodifiable(v)),
      ),
    );
  }

  @override
  Future<DeviceHistorySummary?> queryDeviceSummary(
    String deviceId, {
    required Map<String, String> aliases,
  }) async {
    final db = _db;
    if (db == null) return null;

    final rows = await db.rawQuery(
      '''
      SELECT d.device_id, d.last_ip, d.mac, d.hostname, d.vendor,
             d.is_randomized_mac, d.first_seen_ms, d.last_seen_ms,
             COALESCE(SUM(u.download_bytes), 0) AS rx,
             COALESCE(SUM(u.upload_bytes), 0) AS tx
      FROM devices d
      LEFT JOIN usage_buckets u ON u.device_id = d.device_id
      WHERE d.device_id = ?
      GROUP BY d.device_id
      ''',
      [deviceId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return DeviceHistorySummary(
      deviceId: deviceId,
      ip: (row['last_ip'] as String?) ?? deviceId,
      mac: row['mac'] as String?,
      hostname: row['hostname'] as String?,
      vendor: (row['vendor'] as String?) ?? 'Unknown',
      isRandomizedMac: ((row['is_randomized_mac'] as num?)?.toInt() ?? 0) == 1,
      customAlias: aliases[deviceId],
      downloadBytes: (row['rx'] as num?)?.toInt() ?? 0,
      uploadBytes: (row['tx'] as num?)?.toInt() ?? 0,
      firstSeenMs: (row['first_seen_ms'] as num?)?.toInt() ?? 0,
      lastSeenMs: (row['last_seen_ms'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<DeviceHistorySummary>> queryAllDevices({
    required Map<String, String> aliases,
  }) async {
    final db = _db;
    if (db == null) return const [];

    final rows = await db.rawQuery(
      '''
      SELECT d.device_id, d.last_ip, d.mac, d.hostname, d.vendor,
             d.is_randomized_mac, d.first_seen_ms, d.last_seen_ms,
             COALESCE(SUM(u.download_bytes), 0) AS rx,
             COALESCE(SUM(u.upload_bytes), 0) AS tx
      FROM devices d
      LEFT JOIN usage_buckets u ON u.device_id = d.device_id
      WHERE d.device_id != '_hotspot_total_'
      GROUP BY d.device_id
      ORDER BY d.last_seen_ms DESC
      ''',
    );

    return rows.map((row) {
      final id = (row['device_id'] as String?) ?? 'unknown';
      return DeviceHistorySummary(
        deviceId: id,
        ip: (row['last_ip'] as String?) ?? id,
        mac: row['mac'] as String?,
        hostname: row['hostname'] as String?,
        vendor: (row['vendor'] as String?) ?? 'Unknown',
        isRandomizedMac: ((row['is_randomized_mac'] as num?)?.toInt() ?? 0) == 1,
        customAlias: aliases[id],
        downloadBytes: (row['rx'] as num?)?.toInt() ?? 0,
        uploadBytes: (row['tx'] as num?)?.toInt() ?? 0,
        firstSeenMs: (row['first_seen_ms'] as num?)?.toInt() ?? 0,
        lastSeenMs: (row['last_seen_ms'] as num?)?.toInt() ?? 0,
      );
    }).toList(growable: false);
  }

  @override
  Future<void> clearAll() async {
    final db = _db;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete('usage_buckets');
      await txn.delete('devices');
    });
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static List<TimelinePoint> _aggregateTimeline(
    HistoryRange range,
    List<(int hourMs, int rx, int tx)> hourPoints,
    DateTime now,
  ) {
    if (hourPoints.isEmpty) return const [];
    final byBucket = <int, (String label, int rx, int tx)>{};

    for (final (hourMs, rx, tx) in hourPoints) {
      final dt = DateTime.fromMillisecondsSinceEpoch(hourMs);
      final int key;
      final String label;
      switch (range) {
        case HistoryRange.hour:
        case HistoryRange.day:
          key = hourMs;
          label = '${dt.hour.toString().padLeft(2, '0')}:00';
        case HistoryRange.month:
          key = DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
          label = '${dt.day}';
        case HistoryRange.year:
        case HistoryRange.all:
          key = DateTime(dt.year, dt.month, 1).millisecondsSinceEpoch;
          const months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
          ];
          label = range == HistoryRange.all
              ? '${months[dt.month - 1]} ${dt.year % 100}'
              : months[dt.month - 1];
      }

      final prev = byBucket[key];
      if (prev == null) {
        byBucket[key] = (label, rx, tx);
      } else {
        byBucket[key] = (label, prev.$2 + rx, prev.$3 + tx);
      }
    }

    final keys = byBucket.keys.toList()..sort();
    return keys
        .map((k) {
          final entry = byBucket[k]!;
          return TimelinePoint(
            label: entry.$1,
            bucketStartMs: k,
            downloadBytes: entry.$2,
            uploadBytes: entry.$3,
          );
        })
        .toList(growable: false);
  }
}

/// Lightweight in-memory store used in widget & unit tests.
class InMemoryHistoryStore implements HistoryStore {
  final Map<String, DeviceHistorySummary> _devices = {};
  final Map<(int, String, String), ({String name, String cat, List<String> domains, List<EndpointUsage> endpoints, int rx, int tx, int lastMs})>
      _buckets = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> recordBatch({
    required int timestampMs,
    required List<ConnectedDevice> devices,
    required List<UsageDeltaRecord> deltas,
  }) async {
    final bucketHour = localHourBucketStartMs(
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
    for (final d in devices) {
      final prev = _devices[d.id];
      final effectiveLastSeen = d.isOnline
          ? timestampMs
          : (prev?.lastSeenMs ?? (d.lastSeenMs > 0 ? d.lastSeenMs : timestampMs));
      _devices[d.id] = DeviceHistorySummary(
        deviceId: d.id,
        ip: d.ip,
        mac: d.mac ?? prev?.mac,
        hostname: d.hostname ?? prev?.hostname,
        vendor: d.vendor,
        isRandomizedMac: d.isRandomizedMac,
        customAlias: d.customAlias,
        downloadBytes: 0,
        uploadBytes: 0,
        firstSeenMs: prev?.firstSeenMs ?? timestampMs,
        lastSeenMs: effectiveLastSeen,
      );
    }
    for (final delta in deltas) {
      if (delta.downloadDelta <= 0 && delta.uploadDelta <= 0) continue;
      final key = (bucketHour, delta.deviceId, delta.serviceId);
      final prev = _buckets[key];
      _buckets[key] = (
        name: delta.displayName,
        cat: delta.category,
        domains: delta.topDomains.isNotEmpty ? delta.topDomains : (prev?.domains ?? const []),
        endpoints: _mergeEndpointLists(prev?.endpoints ?? const [], delta.endpoints),
        rx: (prev?.rx ?? 0) + delta.downloadDelta,
        tx: (prev?.tx ?? 0) + delta.uploadDelta,
        lastMs: timestampMs,
      );
    }
  }

  @override
  Future<UsageReport> queryReport({
    required HistoryRange range,
    required Map<String, String> aliases,
    String? deviceId,
    DateTime? now,
  }) async {
    final refNow = now ?? DateTime.now();
    final minHour = rangeStartMs(range, refNow);

    var totalRx = 0;
    var totalTx = 0;
    final hourMap = <int, (int rx, int tx)>{};
    final svcMap = <String, ({String name, String cat, List<String> domains, List<EndpointUsage> endpoints, int rx, int tx, int lastMs})>{};
    final perDevSvcMap = <String, Map<String, ({String name, String cat, List<String> domains, List<EndpointUsage> endpoints, int rx, int tx, int lastMs})>>{};
    final devTotals = <String, (int rx, int tx)>{};

    for (final entry in _buckets.entries) {
      final (hourMs, dId, sId) = entry.key;
      if (hourMs < minHour) continue;
      if (deviceId != null && dId != deviceId) continue;

      final v = entry.value;
      totalRx += v.rx;
      totalTx += v.tx;

      final hPrev = hourMap[hourMs] ?? (0, 0);
      hourMap[hourMs] = (hPrev.$1 + v.rx, hPrev.$2 + v.tx);

      final sPrev = svcMap[sId];
      svcMap[sId] = (
        name: v.name,
        cat: v.cat,
        domains: v.domains.isNotEmpty ? v.domains : (sPrev?.domains ?? const []),
        endpoints: _mergeEndpointLists(sPrev?.endpoints ?? const [], v.endpoints),
        rx: (sPrev?.rx ?? 0) + v.rx,
        tx: (sPrev?.tx ?? 0) + v.tx,
        lastMs: v.lastMs,
      );

      final devSvcs = perDevSvcMap.putIfAbsent(dId, () => {});
      final dsPrev = devSvcs[sId];
      devSvcs[sId] = (
        name: v.name,
        cat: v.cat,
        domains: v.domains.isNotEmpty ? v.domains : (dsPrev?.domains ?? const []),
        endpoints: _mergeEndpointLists(dsPrev?.endpoints ?? const [], v.endpoints),
        rx: (dsPrev?.rx ?? 0) + v.rx,
        tx: (dsPrev?.tx ?? 0) + v.tx,
        lastMs: v.lastMs,
      );

      final dPrev = devTotals[dId] ?? (0, 0);
      devTotals[dId] = (dPrev.$1 + v.rx, dPrev.$2 + v.tx);
    }

    final servicesByDevice = <String, List<ServiceUsage>>{};
    for (final dEntry in perDevSvcMap.entries) {
      final list = dEntry.value.entries
          .map(
            (e) => ServiceUsage(
              serviceId: e.key,
              displayName: e.value.name,
              category: e.value.cat,
              downloadBytes: e.value.rx,
              uploadBytes: e.value.tx,
              topDomains: e.value.domains,
              lastActiveMs: e.value.lastMs,
              endpoints: e.value.endpoints,
            ),
          )
          .toList()
        ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
      servicesByDevice[dEntry.key] = List<ServiceUsage>.unmodifiable(list);
    }

    final services = svcMap.entries
        .map(
          (e) => ServiceUsage(
            serviceId: e.key,
            displayName: e.value.name,
            category: e.value.cat,
            downloadBytes: e.value.rx,
            uploadBytes: e.value.tx,
            topDomains: e.value.domains,
            lastActiveMs: e.value.lastMs,
            endpoints: e.value.endpoints,
          ),
        )
        .toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    final devices = devTotals.entries
        .map((e) {
          final meta = _devices[e.key];
          return DeviceHistorySummary(
            deviceId: e.key,
            ip: meta?.ip ?? e.key,
            mac: meta?.mac,
            hostname: meta?.hostname,
            vendor: meta?.vendor ?? 'Unknown',
            isRandomizedMac: meta?.isRandomizedMac ?? false,
            customAlias: aliases[e.key],
            downloadBytes: e.value.$1,
            uploadBytes: e.value.$2,
            firstSeenMs: meta?.firstSeenMs ?? 0,
            lastSeenMs: meta?.lastSeenMs ?? 0,
          );
        })
        .toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    final hourList = hourMap.entries
        .map((e) => (e.key, e.value.$1, e.value.$2))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    return UsageReport(
      range: range,
      totalDownloadBytes: totalRx,
      totalUploadBytes: totalTx,
      timeline: SqliteHistoryStore._aggregateTimeline(range, hourList, refNow),
      devices: devices,
      services: services,
      servicesByDevice: servicesByDevice,
    );
  }

  @override
  Future<DeviceHistorySummary?> queryDeviceSummary(
    String deviceId, {
    required Map<String, String> aliases,
  }) async {
    final meta = _devices[deviceId];
    if (meta == null) return null;
    final report = await queryReport(
      range: HistoryRange.all,
      aliases: aliases,
      deviceId: deviceId,
    );
    return DeviceHistorySummary(
      deviceId: deviceId,
      ip: meta.ip,
      mac: meta.mac,
      hostname: meta.hostname,
      vendor: meta.vendor,
      isRandomizedMac: meta.isRandomizedMac,
      customAlias: aliases[deviceId],
      downloadBytes: report.totalDownloadBytes,
      uploadBytes: report.totalUploadBytes,
      firstSeenMs: meta.firstSeenMs,
      lastSeenMs: meta.lastSeenMs,
    );
  }

  @override
  Future<List<DeviceHistorySummary>> queryAllDevices({
    required Map<String, String> aliases,
  }) async {
    final list = <DeviceHistorySummary>[];
    for (final meta in _devices.values) {
      if (meta.deviceId == '_hotspot_total_') continue;
      final summary = await queryDeviceSummary(meta.deviceId, aliases: aliases);
      if (summary != null) list.add(summary);
    }
    list.sort((a, b) => b.lastSeenMs.compareTo(a.lastSeenMs));
    return list;
  }

  @override
  Future<void> clearAll() async {
    _devices.clear();
    _buckets.clear();
  }

  @override
  Future<void> close() async {}
}
