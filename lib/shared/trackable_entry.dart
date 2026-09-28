/// The shared data shape every widget module builds on.
///
/// Finance, Tasks, Work hours, and Health all log entries that boil down
/// to "something happened, at some time, with some value." Keeping one
/// shared model here means new modules don't need new storage code —
/// they just fill in these fields differently.
class TrackableEntry {
  final String id;
  final String moduleType; // e.g. "finance", "task", "workHours", "health"
  final String category; // e.g. "groceries", "chest day", "clocked in"
  final double? value; // amount spent, hours worked, weight logged, etc.
  final DateTime timestamp;
  final String? note;
  final bool isComplete; // used by tasks; ignored by other modules

  /// Where this entry came from -- e.g. "mock", "manual", "plaid".
  /// Added for the Finance module's manual-entry feature, which needs to
  /// tell user-entered entries apart from synced/generated ones. Defaults
  /// to "mock" so every existing call site (generateMockEntries(), etc.)
  /// keeps compiling without needing to pass this explicitly.
  final String source;

  const TrackableEntry({
    required this.id,
    required this.moduleType,
    required this.category,
    this.value,
    required this.timestamp,
    this.note,
    this.isComplete = false,
    this.source = 'mock',
  });

  factory TrackableEntry.fromMap(Map<String, dynamic> map) {
    return TrackableEntry(
      id: map['id'] as String,
      moduleType: map['moduleType'] as String,
      category: map['category'] as String,
      value: map['value'] as double?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      note: map['note'] as String?,
      isComplete: (map['isComplete'] as int?) == 1,
      source: (map['source'] as String?) ?? 'mock',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'moduleType': moduleType,
      'category': category,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'note': note,
      'isComplete': isComplete ? 1 : 0,
      'source': source,
    };
  }
}