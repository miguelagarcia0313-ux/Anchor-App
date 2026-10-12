# WorkManager (pulled in by plugins) creates its Room database by reflection.
# R8 can't see that, so it strips the constructor -> startup crash in release.
-keep class * extends androidx.room.RoomDatabase { <init>(...); }
-keep class androidx.work.impl.** { *; }