DateTime? parseTaskDateTime(String text, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final timeMatch = RegExp(
    r'\b(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\s*(am|pm)\b',
    caseSensitive: false,
  ).firstMatch(text);
  final time = _parseTime(timeMatch);
  final date =
      _parseExplicitDate(text, current) ?? _parseWeekday(text, current, time);

  if (date == null) {
    return null;
  }
  return DateTime(
    date.year,
    date.month,
    date.day,
    time?.hour ?? 23,
    time?.minute ?? 59,
  );
}

DateTime? _parseExplicitDate(String text, DateTime current) {
  final isoMatch = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(text);
  if (isoMatch != null) {
    return _validDate(
      int.parse(isoMatch.group(1)!),
      int.parse(isoMatch.group(2)!),
      int.parse(isoMatch.group(3)!),
    );
  }

  final numericMatch = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b')
      .firstMatch(text);
  if (numericMatch != null) {
    var year = numericMatch.group(3) == null
        ? current.year
        : int.parse(numericMatch.group(3)!);
    if (year < 100) {
      year += year < 50 ? 2000 : 1900;
    }
    final month = int.parse(numericMatch.group(1)!);
    final day = int.parse(numericMatch.group(2)!);
    final parsedDate = _validDate(year, month, day);
    if (parsedDate == null || numericMatch.group(3) != null) {
      return parsedDate;
    }
    if (_startOfDay(parsedDate).isBefore(_startOfDay(current))) {
      return _validDate(year + 1, month, day);
    }
    return parsedDate;
  }

  final monthMatch = RegExp(
    r'\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})(?:,?\s+(\d{4}))?\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (monthMatch == null) {
    return null;
  }

  const months = <String>[
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];
  final month = months.indexOf(monthMatch.group(1)!.toLowerCase()) + 1;
  final day = int.parse(monthMatch.group(2)!);
  final year = monthMatch.group(3) == null
      ? current.year
      : int.parse(monthMatch.group(3)!);
  final parsedDate = _validDate(year, month, day);
  if (parsedDate == null || monthMatch.group(3) != null) {
    return parsedDate;
  }
  if (_startOfDay(parsedDate).isBefore(_startOfDay(current))) {
    return _validDate(year + 1, month, day);
  }
  return parsedDate;
}

DateTime? _parseWeekday(String text, DateTime current, _ParsedTime? time) {
  final weekdayMatch = RegExp(
    r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (weekdayMatch == null) {
    return null;
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
  final targetWeekday =
      weekdays.indexOf(weekdayMatch.group(1)!.toLowerCase()) + DateTime.monday;
  var daysAhead = targetWeekday - current.weekday;
  if (daysAhead < 0 ||
      (daysAhead == 0 &&
          time != null &&
          !DateTime(
            current.year,
            current.month,
            current.day,
            time.hour,
            time.minute,
          ).isAfter(current))) {
    daysAhead += DateTime.daysPerWeek;
  }
  final date = current.add(Duration(days: daysAhead));
  return DateTime(date.year, date.month, date.day);
}

_ParsedTime? _parseTime(RegExpMatch? timeMatch) {
  if (timeMatch == null) {
    return null;
  }
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
  return _ParsedTime(hour, minute);
}

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

DateTime _startOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

class _ParsedTime {
  const _ParsedTime(this.hour, this.minute);

  final int hour;
  final int minute;
}
