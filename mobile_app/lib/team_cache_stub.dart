import 'team_cache.dart';

/// No saved copy where there's no file system (the web).
class DeviceTeamCacheStore implements TeamCacheStore {
  @override
  Future<Map<String, dynamic>?> read(String userId) async => null;

  @override
  Future<void> write(String userId, Map<String, dynamic> data) async {}

  @override
  Future<void> clear() async {}
}
