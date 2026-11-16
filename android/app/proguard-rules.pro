# Picked up automatically by the Flutter Gradle plugin for release builds.

# WorkManager (home screen widget refresh) creates its Room database by reflection:
# WorkDatabase_Impl.<init>(). R8 stripped that constructor and 1.1.0 crashed at launch
# in androidx.startup.InitializationProvider.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
