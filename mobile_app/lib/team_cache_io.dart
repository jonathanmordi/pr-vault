import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'team_cache.dart';

/// One gzipped JSON file per user in the app's cache folder, which the
/// system may clear when space runs low; then the app just downloads again.
/// Encoding and decoding run on a background isolate so they never hold up
/// a frame.
class DeviceTeamCacheStore implements TeamCacheStore {
  static const _prefix = 'team_';

  Future<Directory> _dir() => getApplicationCacheDirectory();

  Future<File> _file(String userId) async =>
      File('${(await _dir()).path}/$_prefix${userId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}.json.gz');

  @override
  Future<Map<String, dynamic>?> read(String userId) async {
    final path = (await _file(userId)).path;
    return Isolate.run(() {
      final file = File(path);
      if (!file.existsSync()) return null;
      return jsonDecode(utf8.decode(gzip.decode(file.readAsBytesSync()))) as Map<String, dynamic>;
    });
  }

  @override
  Future<void> write(String userId, Map<String, dynamic> data) async {
    final path = (await _file(userId)).path;
    await Isolate.run(() {
      // Written aside and moved into place, so a crash mid-write never
      // leaves a half-written copy.
      final tmp = File('$path.tmp')..writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(data))));
      tmp.renameSync(path);
    });
  }

  @override
  Future<void> clear() async {
    final dir = await _dir();
    if (!dir.existsSync()) return;
    for (final f in dir.listSync()) {
      final name = f.uri.pathSegments.last;
      if (f is File && name.startsWith(_prefix) && name.contains('.json.gz')) f.deleteSync();
    }
  }
}
