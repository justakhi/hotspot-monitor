import 'package:flutter_test/flutter_test.dart';
import 'package:hotspot_monitor/domain/models/history_report.dart';
import 'package:hotspot_monitor/ui/core/utils/formatters.dart';

void main() {
  group('Formatters', () {
    test('formats byte sizes cleanly across units', () {
      expect(Formatters.bytes(0), '0 B');
      expect(Formatters.bytes(512), '512 B');
      expect(Formatters.bytes(1024), '1.00 KB');
      expect(Formatters.bytes(15 * 1024 * 1024), '15.0 MB');
      expect(Formatters.bytes(2 * 1024 * 1024 * 1024), '2.00 GB');
    });

    test('formats speeds and signal strength labels', () {
      expect(Formatters.speed(0), '0 B/s');
      expect(Formatters.speed(2048), '2.00 KB/s');
      expect(Formatters.signalLabel(null), 'Unknown');
      expect(Formatters.signalLabel(-45), 'Excellent (-45 dBm)');
      expect(Formatters.signalLabel(-72), 'Fair (-72 dBm)');
    });

    test('formats exact calendar date and time windows for history ranges', () {
      final now = DateTime(2026, 11, 11, 14, 42);
      expect(
        Formatters.rangeWindow(HistoryRange.hour, now: now),
        '11 Nov 2026, 14:00 - 15:00',
      );
      expect(
        Formatters.rangeWindow(HistoryRange.day, now: now),
        '11 Nov 2026, 00:00 - 14:42',
      );
      expect(
        Formatters.rangeWindow(HistoryRange.month, now: now),
        '1 - 11 Nov 2026',
      );
    });
  });
}
