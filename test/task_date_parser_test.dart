import 'package:flutter_test/flutter_test.dart';

import 'package:anchor_app/modules/tasks/task_date_parser.dart';

void main() {
  test('parses a time and weekday into the next matching date', () {
    final result = parseTaskDateTime(
      'Call dentist 3AM Wednesday',
      now: DateTime(2026, 9, 25, 12),
    );

    expect(result, DateTime(2026, 9, 30, 3));
  });

  test('uses the same day when the parsed time is still ahead', () {
    final result = parseTaskDateTime(
      '3AM Wednesday',
      now: DateTime(2026, 9, 30, 1),
    );

    expect(result, DateTime(2026, 9, 30, 3));
  });

  test('returns null when a complete date and time are not present', () {
    expect(parseTaskDateTime('Call dentist Wednesday'), isNull);
    expect(parseTaskDateTime('Call dentist 3AM'), isNull);
  });
}