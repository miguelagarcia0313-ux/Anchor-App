DateTime? parseTaskDateTime(String text, {DateTime? now}) {
  final timeMatch = RegExp(
    r'\b(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\s*(am|pm)\b',
    caseSensitive: false,
  ).firstMatch(text);
  final weekdayMatch = RegExp(
    r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
    caseSensitive: false,
  ).firstMatch(text);

  if (timeMatch == null || weekdayMatch == null) {
    return null;
  }

  final current = now ?? DateTime.now();
  var hour = int.parse(timeMatch.group(1)!);
  final minute = int.parse(timeMatch.group(2) ?? '0');
  final period = timeMatch.group(3)!.toLowerCase();
  if (period == 'am') {
    if (hour == 12) {
      hour = 0;
    }
  } else if (hour != 12) {
    hour += 12;
  }

  const weekdays = <String>[
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final targetWeekday = weekdays.indexOf(weekdayMatch.group(1)!.toLowerCase()) +
      DateTime.monday;
  var daysAhead = targetWeekday - current.weekday;
  if (daysAhead < 0 ||
      (daysAhead == 0 &&
          !DateTime(current.year, current.month, current.day, hour, minute)
              .isAfter(current))) {
    daysAhead += DateTime.daysPerWeek;
  }

  final date = current.add(Duration(days: daysAhead));
  return DateTime(date.year, date.month, date.day, hour, minute);
}