// A copy of the team's data saved on the phone, so the app can show it the
// moment it opens and while offline. The latest data still comes from the
// server; this is only the starting point.

import 'team_cache_stub.dart' if (dart.library.io) 'team_cache_io.dart' as impl;

/// Saves and reads one JSON-like map per user.
abstract class TeamCacheStore {
  Future<Map<String, dynamic>?> read(String userId);
  Future<void> write(String userId, Map<String, dynamic> data);

  /// Removes every user's copy, e.g. on sign-out.
  Future<void> clear();

  /// Files on phones; nothing on the web.
  factory TeamCacheStore.device() = impl.DeviceTeamCacheStore;
}

/// Keeps copies in memory, for tests.
class MemoryTeamCacheStore implements TeamCacheStore {
  final copies = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> read(String userId) async => copies[userId];

  @override
  Future<void> write(String userId, Map<String, dynamic> data) async => copies[userId] = data;

  @override
  Future<void> clear() async => copies.clear();
}
