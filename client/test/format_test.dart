import 'package:client/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(0), '0 KB');
    expect(formatBytes(1536), '2 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });

  test('formatDate and formatDateTime', () {
    expect(formatDate(DateTime(2026, 10, 28)), '28 Oct 2026');
    expect(formatDateTime(DateTime(2026, 10, 28, 21, 5)), '28 Oct 2026, 21:05');
  });

  test('timeAgo', () {
    final now = DateTime(2026, 10, 28, 12);
    String ago(Duration d) => timeAgo(now.subtract(d), now: now);

    expect(ago(const Duration(seconds: 30)), 'just now');
    expect(ago(const Duration(minutes: 5)), '5 min ago');
    expect(ago(const Duration(hours: 3)), '3 h ago');
    expect(ago(const Duration(days: 1)), '1 day ago');
    expect(ago(const Duration(days: 3)), '3 days ago');
    expect(ago(const Duration(days: 45)), '1 month ago');
    expect(ago(const Duration(days: 60)), '2 months ago');
    expect(ago(const Duration(days: 400)), '1 year ago');
  });

  test('greeting follows the hour', () {
    expect(greeting(now: DateTime(2026, 1, 1, 9)), 'Good morning');
    expect(greeting(now: DateTime(2026, 1, 1, 14)), 'Good afternoon');
    expect(greeting(now: DateTime(2026, 1, 1, 20)), 'Good evening');
  });

  test('secondsLabel', () {
    expect(secondsLabel(0), 'Immediately');
    expect(secondsLabel(30), '30 seconds');
    expect(secondsLabel(60), '1 minute');
    expect(secondsLabel(300), '5 minutes');
  });
}
