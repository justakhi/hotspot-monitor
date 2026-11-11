import '../../../domain/models/history_report.dart';

/// Formatting helpers for byte counts, speeds, durations, dates, and signal quality.
class Formatters {
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static String bytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    if (unitIndex == 0) return '${value.toInt()} B';
    if (value >= 100) return '${value.toStringAsFixed(0)} ${units[unitIndex]}';
    if (value >= 10) return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
    return '${value.toStringAsFixed(2)} ${units[unitIndex]}';
  }

  static String speed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    return '${bytes(bytesPerSecond)}/s';
  }

  static String durationSince(int startMs, {int? nowMs}) {
    if (startMs <= 0) return '00:00';
    final end = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final diffSec = ((end - startMs) / 1000).floor().clamp(0, 8640000);
    final hours = diffSec ~/ 3600;
    final minutes = (diffSec % 3600) ~/ 60;
    final seconds = diffSec % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static String signalLabel(int? rssiDbm) {
    if (rssiDbm == null) return 'Unknown';
    if (rssiDbm >= -55) return 'Excellent ($rssiDbm dBm)';
    if (rssiDbm >= -67) return 'Good ($rssiDbm dBm)';
    if (rssiDbm >= -78) return 'Fair ($rssiDbm dBm)';
    return 'Weak ($rssiDbm dBm)';
  }

  static String shortTimestamp(int timestampMs, {DateTime? now}) {
    if (timestampMs <= 0) return 'Unknown';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final ref = now ?? DateTime.now();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final sameDay = dt.year == ref.year && dt.month == ref.month && dt.day == ref.day;
    if (sameDay) return 'Today $hh:$mm';
    return '${dt.day} ${_months[dt.month - 1]} $hh:$mm';
  }

  static String fullDateTime(int timestampMs) {
    if (timestampMs <= 0) return 'Unknown';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}, $hh:$mm';
  }

  static String relativeAgo(int timestampMs, {DateTime? now}) {
    if (timestampMs <= 0) return 'Unknown';
    final ref = now ?? DateTime.now();
    final diffSec = ((ref.millisecondsSinceEpoch - timestampMs) / 1000).floor();
    if (diffSec < 60) return 'Just now';
    final mins = diffSec ~/ 60;
    if (mins < 60) return '${mins}m ago';
    final hours = mins ~/ 60;
    if (hours < 24) return '${hours}h ${mins % 60}m ago';
    final days = hours ~/ 24;
    return '${days}d ago';
  }

  static String rangeWindow(
    HistoryRange range, {
    DateTime? now,
    int? firstSeenMs,
  }) {
    final ref = now ?? DateTime.now();
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    switch (range) {
      case HistoryRange.hour:
        final start = DateTime(ref.year, ref.month, ref.day, ref.hour);
        final end = start.add(const Duration(hours: 1));
        return '${start.day} ${_months[start.month - 1]} ${start.year}, ${hhmm(start)} - ${hhmm(end)}';
      case HistoryRange.day:
        return '${ref.day} ${_months[ref.month - 1]} ${ref.year}, 00:00 - ${hhmm(ref)}';
      case HistoryRange.month:
        return '1 - ${ref.day} ${_months[ref.month - 1]} ${ref.year}';
      case HistoryRange.year:
        return '1 Jan - ${ref.day} ${_months[ref.month - 1]} ${ref.year}';
      case HistoryRange.all:
        if (firstSeenMs != null && firstSeenMs > 0) {
          return '${fullDateTime(firstSeenMs)} - Now';
        }
        return 'All recorded history up to ${hhmm(ref)}';
    }
  }

  static String timelineBucketDetail(int bucketStartMs, HistoryRange? range) {
    if (bucketStartMs <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(bucketStartMs);
    final hh = dt.hour.toString().padLeft(2, '0');
    final nextHh = ((dt.hour + 1) % 24).toString().padLeft(2, '0');
    if (range == HistoryRange.hour || range == HistoryRange.day) {
      return '${dt.day} ${_months[dt.month - 1]} ${dt.year}, $hh:00 - $nextHh:00';
    }
    if (range == HistoryRange.year || range == HistoryRange.all) {
      return '${_months[dt.month - 1]} ${dt.year}';
    }
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }
}
