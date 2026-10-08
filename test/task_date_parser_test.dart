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

  test('uses today when a time is present without a date', () {
    expect(
      parseTaskDateTime(
        'Sprint due at 11PM',
        now: DateTime(2026, 10, 8, 15, 43),
      ),
      DateTime(2026, 10, 8, 23),
    );
    expect(
      parseTaskDateTime('Sprint due at 11 AM', now: DateTime(2026, 10, 8, 9)),
      DateTime(2026, 10, 8, 11),
    );
  });

  test('returns null when neither a date nor a time is present', () {
    expect(parseTaskDateTime('Call dentist'), isNull);
  });

  test('parses explicit numeric dates without a time', () {
    expect(
      parseTaskDateTime(
        'Submit report 2026-10-08',
        now: DateTime(2026, 9, 25, 12),
      ),
      DateTime(2026, 10, 8, 23, 59),
    );
    expect(
      parseTaskDateTime(
        'Submit report 10/8/2026',
        now: DateTime(2026, 9, 25, 12),
      ),
      DateTime(2026, 10, 8, 23, 59),
    );
    expect(
      parseTaskDateTime('Submit report 10/8', now: DateTime(2026, 9, 25, 12)),
      DateTime(2026, 10, 8, 23, 59),
    );
  });

  test('parses month-name dates and keeps an explicit time', () {
    expect(
      parseTaskDateTime(
        'Meet October 8, 2026 at 3AM',
        now: DateTime(2026, 9, 25, 12),
      ),
      DateTime(2026, 10, 8, 3),
    );
  });

  test('parses ordinal month-name dates and keeps an explicit time', () {
    expect(
      parseTaskDateTime(
        'Posert due October 14th at 8 AM',
        now: DateTime(2026, 10, 8, 15, 43),
      ),
      DateTime(2026, 10, 14, 8),
    );
  });

  test('uses the next year for a past month-name date without a year', () {
    expect(
      parseTaskDateTime(
        'Renew subscription January 4',
        now: DateTime(2026, 9, 25, 12),
      ),
      DateTime(2027, 1, 4, 23, 59),
    );
  });
}
