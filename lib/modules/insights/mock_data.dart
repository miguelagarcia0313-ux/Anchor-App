import '../../shared/trackable_entry.dart';

/// Fake data shaped exactly like [TrackableEntry], so insights logic can be
/// built and tested before persistence (drift/SQLite) is wired up.
///
/// Swap calls to this out for a real repository/database read once
/// persistence exists — everything downstream should keep working
/// unchanged, since it only depends on the TrackableEntry shape.
List<TrackableEntry> generateMockEntries() {
  final now = DateTime.now();
  DateTime daysAgo(int days) => now.subtract(Duration(days: days));

  return [
    // --- Finance entries ---
    TrackableEntry(
      id: 'f1',
      moduleType: 'finance',
      category: 'groceries',
      value: 62.40,
      timestamp: daysAgo(2),
      note: 'H-E-B run',
    ),
    TrackableEntry(
      id: 'f2',
      moduleType: 'finance',
      category: 'eating_out',
      value: 28.75,
      timestamp: daysAgo(3),
      note: 'Chipotle with friends',
    ),
    TrackableEntry(
      id: 'f3',
      moduleType: 'finance',
      category: 'eating_out',
      value: 15.20,
      timestamp: daysAgo(6),
    ),
    TrackableEntry(
      id: 'f4',
      moduleType: 'finance',
      category: 'subscriptions',
      value: 15.99,
      timestamp: daysAgo(10),
      note: 'Spotify',
    ),
    TrackableEntry(
      id: 'f5',
      moduleType: 'finance',
      category: 'eating_out',
      value: 34.10,
      timestamp: daysAgo(12),
    ),
    TrackableEntry(
      id: 'f6',
      moduleType: 'finance',
      category: 'groceries',
      value: 71.85,
      timestamp: daysAgo(16),
    ),
    TrackableEntry(
      id: 'f7',
      moduleType: 'finance',
      category: 'entertainment',
      value: 42.00,
      timestamp: daysAgo(18),
      note: 'Movie night',
    ),

    // --- Task entries ---
    TrackableEntry(
      id: 't1',
      moduleType: 'task',
      category: 'homework',
      timestamp: daysAgo(1),
      note: 'Finish CS capstone proposal',
      isComplete: true,
    ),
    TrackableEntry(
      id: 't2',
      moduleType: 'task',
      category: 'homework',
      timestamp: daysAgo(0),
      note: 'Study for networking exam',
      isComplete: false,
    ),
    TrackableEntry(
      id: 't3',
      moduleType: 'task',
      category: 'chores',
      timestamp: daysAgo(4),
      note: 'Laundry',
      isComplete: true,
    ),
    TrackableEntry(
      id: 't4',
      moduleType: 'task',
      category: 'homework',
      timestamp: daysAgo(5),
      note: 'Read chapter 3',
      isComplete: false,
    ),

    // --- Health entries (module not built yet, but shape works today) ---
    TrackableEntry(
      id: 'h1',
      moduleType: 'health',
      category: 'weight',
      value: 178.4,
      timestamp: daysAgo(1),
    ),
    TrackableEntry(
      id: 'h2',
      moduleType: 'health',
      category: 'weight',
      value: 179.1,
      timestamp: daysAgo(8),
    ),
  ];
}