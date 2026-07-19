import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_service.dart';
import 'backup_utils.dart';
import 'media_service.dart';

/// 同一 WiFi（路由器）局域网同步：一台手机做主机，其余手机加入，
/// 各自上传数据到主机合并出并集，再从主机下载并集。不经过互联网。
const kSyncBasePort = 47820;
const kBeaconPort = 47821;
const kBeaconMagic = 'BRSYNC1';

class SyncHostInfo {
  final String ip;
  final int port;
  final String name;

  const SyncHostInfo(this.ip, this.port, this.name);
}

/// 隔离线程：把一组文件打成 zip。
Future<void> _zipFiles(Map<String, Object?> args) async {
  final outPath = args['out'] as String;
  final files = (args['files'] as List).cast<Map<String, String>>();
  final encoder = ZipFileEncoder();
  encoder.create(outPath);
  for (final f in files) {
    final file = File(f['src']!);
    if (file.existsSync()) await encoder.addFile(file, f['arc']!);
  }
  await encoder.close();
}

/// 隔离线程：解压 zip 到目录。
Future<void> _unzipTo(Map<String, String> args) async {
  final archive = ZipDecoder().decodeStream(InputFileStream(args['zip']!));
  await extractArchiveToDisk(archive, args['out']!);
}

/// 本机的局域网 IPv4 地址列表。
Future<List<String>> localIpAddresses() async {
  final result = <String>[];
  try {
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final ni in interfaces) {
      for (final addr in ni.addresses) {
        if (!addr.isLoopback) result.add(addr.address);
      }
    }
  } catch (_) {}
  return result;
}

/// 主机会话：等待其他设备上传，合并后分发并集。
class SyncHostSession {
  final String name;
  final void Function(String line) onLog;
  final void Function() onChanged;

  SyncHostSession(
      {required this.name, required this.onLog, required this.onChanged});

  HttpServer? _server;
  RawDatagramSocket? _beacon;
  Timer? _beaconTimer;
  Directory? _tempDir;

  int port = 0;
  String code = '';
  int receivedCount = 0;
  bool unionReady = false;
  bool _stopped = false;
  Map<String, dynamic>? _unionTables;

  Future<void> start() async {
    // 端口冲突时顺延尝试。
    Object? lastError;
    for (var pCandidate = kSyncBasePort;
        pCandidate < kSyncBasePort + 8;
        pCandidate++) {
      try {
        _server = await HttpServer.bind(
            InternetAddress.anyIPv4, pCandidate);
        port = pCandidate;
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (_server == null) {
      throw StateError('无法启动同步服务：$lastError');
    }
    code = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    _tempDir = Directory(p.join(
        (await getTemporaryDirectory()).path, 'sync_host_$code'));
    await _tempDir!.create(recursive: true);

    // UDP 广播自己的存在（自动发现）。
    try {
      _beacon = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
        ..broadcastEnabled = true;
      _beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        try {
          _beacon?.send(
              utf8.encode('$kBeaconMagic|$name|$port'),
              InternetAddress('255.255.255.255'),
              kBeaconPort);
        } catch (_) {}
      });
    } catch (_) {
      // 广播失败不影响手动 IP 连接。
    }

    _server!.listen(_handle);
    onLog('同步服务已启动，等待家人加入…');
  }

  bool _checkCode(HttpRequest req) =>
      req.uri.queryParameters['code'] == code;

  Future<void> _replyJson(HttpRequest req, Object data,
      {int status = 200}) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data));
    await req.response.close();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (_stopped) {
        await _replyJson(req, {'error': 'stopped'}, status: 410);
        return;
      }
      final path = req.uri.path;
      if (path == '/info' && req.method == 'GET') {
        await _replyJson(req, {'name': name, 'ok': true});
        return;
      }
      if (!_checkCode(req)) {
        await _replyJson(req, {'error': '同步码错误'}, status: 403);
        return;
      }
      if (unionReady && (path == '/manifest' || path == '/media')) {
        await _replyJson(req, {'error': '主机已完成合并，请重新发起一轮同步'},
            status: 409);
        return;
      }
      switch ((req.method, path)) {
        case ('POST', '/manifest'):
          await _onManifest(req);
        case ('POST', '/media'):
          await _onMedia(req);
        case ('GET', '/union_state'):
          await _replyJson(req, {'ready': unionReady});
        case ('GET', '/union_manifest'):
          if (_unionTables == null) {
            await _replyJson(req, {'error': '尚未完成合并'}, status: 409);
          } else {
            await _replyJson(req, {
              'app': 'baby_record',
              'formatVersion': 2,
              'tables': _unionTables,
            });
          }
        case ('POST', '/union_media'):
          await _onUnionMedia(req);
        default:
          await _replyJson(req, {'error': '未知请求'}, status: 404);
      }
    } catch (e) {
      try {
        await _replyJson(req, {'error': '$e'}, status: 500);
      } catch (_) {}
    }
  }

  Future<void> _onManifest(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final device = (data['device'] as String?) ?? '家人';
    final error = validateBackupManifest(data);
    if (error != null) {
      await _replyJson(req, {'error': error}, status: 400);
      return;
    }
    final tables = data['tables'] as Map<String, dynamic>;
    final (newBabies, newMoments) =
        await BackupService.instance.mergeTables(tables);
    receivedCount++;
    onLog('已接收「$device」的数据：新增 $newBabies 个档案、$newMoments 条记录');
    // 告诉对方：主机已拥有哪些媒体文件（对方就无需重复上传）。
    final have = referencedFiles(await BackupService.instance.dumpTables());
    await _replyJson(req, {'ok': true, 'have': have.toList()});
    onChanged();
  }

  Future<void> _onMedia(HttpRequest req) async {
    final from = req.uri.queryParameters['from'] ?? '家人';
    final zipFile = File(p.join(
        _tempDir!.path, 'media_${DateTime.now().millisecondsSinceEpoch}.zip'));
    final sink = zipFile.openWrite();
    await sink.addStream(req);
    await sink.close();
    final outDir = Directory(p.join(
        _tempDir!.path, 'ex_${DateTime.now().millisecondsSinceEpoch}'));
    await outDir.create(recursive: true);
    await compute(_unzipTo, {'zip': zipFile.path, 'out': outDir.path});
    var count = 0;
    count += await BackupService.instance.moveMediaIn(outDir, 'media');
    count += await BackupService.instance.moveMediaIn(outDir, 'avatars');
    try {
      await zipFile.delete();
      await outDir.delete(recursive: true);
    } catch (_) {}
    onLog('已接收「$from」的 $count 个照片/视频文件');
    await _replyJson(req, {'ok': true, 'count': count});
    onChanged();
  }

  Future<void> _onUnionMedia(HttpRequest req) async {
    if (_unionTables == null) {
      await _replyJson(req, {'error': '尚未完成合并'}, status: 409);
      return;
    }
    final body = await utf8.decoder.bind(req).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final have = <String>{
      for (final f in (data['have'] as List? ?? [])) '$f'
    };
    final missing = referencedFiles(_unionTables!).difference(have);
    final files = <Map<String, String>>[];
    for (final rel in missing) {
      final full = rel.startsWith('avatars/')
          ? p.join(MediaPaths.avatarBase!, rel.substring(8))
          : p.join(MediaPaths.mediaBase!, rel.substring(6));
      if (File(full).existsSync()) files.add({'src': full, 'arc': rel});
    }
    final zipPath = p.join(_tempDir!.path,
        'union_media_${DateTime.now().millisecondsSinceEpoch}.zip');
    await compute(_zipFiles, {'out': zipPath, 'files': files});
    final zipFile = File(zipPath);
    req.response.headers.contentType = ContentType.binary;
    req.response.headers.set('X-File-Count', files.length);
    req.response.contentLength = await zipFile.length();
    await req.response.addStream(zipFile.openRead());
    await req.response.close();
    try {
      await zipFile.delete();
    } catch (_) {}
  }

  /// 主机端点"完成并分发"：合并出并集供下载。
  Future<void> finishUnion() async {
    _unionTables = await BackupService.instance.dumpTables();
    unionReady = true;
    onLog('已合并出并集，正在分发给家人…');
    onChanged();
  }

  Future<void> stop() async {
    _stopped = true;
    _beaconTimer?.cancel();
    try {
      _beacon?.close();
    } catch (_) {}
    try {
      await _server?.close(force: true);
    } catch (_) {}
    try {
      if (_tempDir != null && _tempDir!.existsSync()) {
        await _tempDir!.delete(recursive: true);
      }
    } catch (_) {}
  }
}

/// 加入方：发现主机并执行完整同步流程。
class SyncJoinResult {
  final String hostName;
  final int uploadedMedia;
  final int newBabies;
  final int newMoments;
  final int downloadedMedia;

  const SyncJoinResult(this.hostName, this.uploadedMedia, this.newBabies,
      this.newMoments, this.downloadedMedia);
}

class SyncClient {
  /// UDP 广播自动发现主机（监听 [timeout] 时长）。
  static Future<List<SyncHostInfo>> discover(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final found = <String, SyncHostInfo>{};
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, kBeaconPort,
          reuseAddress: true);
      final activeSocket = socket;
      subscription = activeSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = activeSocket.receive();
          if (dg == null) return;
          final msg = utf8.decode(dg.data, allowMalformed: true);
          final parts = msg.split('|');
          if (parts.length == 3 && parts[0] == kBeaconMagic) {
            found['${dg.address.address}:${parts[2]}'] = SyncHostInfo(
                dg.address.address, int.tryParse(parts[2]) ?? kSyncBasePort,
                parts[1]);
          }
        }
      });
      await Future<void>.delayed(timeout);
    } catch (_) {} finally {
      try {
        await subscription?.cancel();
        socket?.close();
      } catch (_) {}
    }
    return found.values.toList();
  }

  HttpClient _client() =>
      HttpClient()..connectionTimeout = const Duration(seconds: 10);

  Future<Map<String, dynamic>> _getJson(
      HttpClient client, Uri uri) async {
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 15));
    final resp = await req.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder.bind(resp).join();
    final data = jsonDecode(body);
    if (resp.statusCode != 200) {
      throw StateError(
          data is Map && data['error'] != null ? '${data['error']}' : '请求失败 (${resp.statusCode})');
    }
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
      HttpClient client, Uri uri, Object payload) async {
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(payload));
    final resp = await req.close();
    final body = await utf8.decoder.bind(resp).join();
    final data = jsonDecode(body);
    if (resp.statusCode != 200) {
      throw StateError(
          data is Map && data['error'] != null ? '${data['error']}' : '请求失败 (${resp.statusCode})');
    }
    return data as Map<String, dynamic>;
  }

  /// 完整同步流程：上传我的数据 → 等待主机合并 → 下载并集。
  Future<SyncJoinResult> sync({
    required String hostIp,
    required int port,
    required String code,
    required String myName,
    required void Function(String line) log,
  }) async {
    final client = _client();
    final tempDir = Directory(p.join(
        (await getTemporaryDirectory()).path,
        'sync_join_${DateTime.now().millisecondsSinceEpoch}'));
    await tempDir.create(recursive: true);
    try {
      Uri u(String path, [Map<String, String>? q]) => Uri(
          scheme: 'http',
          host: hostIp,
          port: port,
          path: path,
          queryParameters: {'code': code, ...?q});

      log('正在连接主机…');
      final info = await _getJson(client, u('/info'));
      final hostName = (info['name'] as String?) ?? '主机';

      log('正在上传我的数据…');
      final tables = await BackupService.instance.dumpTables();
      final manifestReply = await _postJson(
          client, u('/manifest'), {'device': myName, 'tables': tables});
      final hostHave = <String>{
        for (final f in (manifestReply['have'] as List? ?? [])) '$f'
      };

      // 只上传主机没有的媒体文件（增量，省时省流量）。
      final toSend = <Map<String, String>>[];
      Future<void> collect(Directory dir, String prefix) async {
        if (!dir.existsSync()) return;
        await for (final e in dir.list()) {
          if (e is File) {
            final rel = '$prefix${p.basename(e.path)}';
            if (!hostHave.contains(rel)) {
              toSend.add({'src': e.path, 'arc': rel});
            }
          }
        }
      }

      await collect(await MediaService.instance.mediaDir(), 'media/');
      await collect(await MediaService.instance.avatarDir(), 'avatars/');
      var uploaded = 0;
      if (toSend.isNotEmpty) {
        log('正在上传 ${toSend.length} 个照片/视频…');
        final zipPath = p.join(tempDir.path, 'upload.zip');
        await compute(_zipFiles, {'out': zipPath, 'files': toSend});
        final zipFile = File(zipPath);
        final req = await client.postUrl(u('/media', {'from': myName}));
        req.headers.contentType = ContentType.binary;
        req.contentLength = await zipFile.length();
        await req.addStream(zipFile.openRead());
        final resp = await req.close();
        final body = await utf8.decoder.bind(resp).join();
        if (resp.statusCode != 200) {
          throw StateError('上传媒体失败：$body');
        }
        uploaded =
            (jsonDecode(body) as Map<String, dynamic>)['count'] as int? ??
                toSend.length;
      }

      log('已上传，等待主机合并并分发…（主机端点"完成并分发"）');
      for (;;) {
        await Future.delayed(const Duration(seconds: 2));
        final state = await _getJson(client, u('/union_state'));
        if (state['ready'] == true) break;
      }

      log('正在下载并集数据…');
      final union = await _getJson(client, u('/union_manifest'));
      final unionTables = union['tables'] as Map<String, dynamic>;
      final (newBabies, newMoments) =
          await BackupService.instance.mergeTables(unionTables);

      // 计算本机缺失的媒体并向主机索取。
      final onDisk = <String>{};
      Future<void> scan(Directory dir, String prefix) async {
        if (!dir.existsSync()) return;
        await for (final e in dir.list()) {
          if (e is File) onDisk.add('$prefix${p.basename(e.path)}');
        }
      }

      await scan(await MediaService.instance.mediaDir(), 'media/');
      await scan(await MediaService.instance.avatarDir(), 'avatars/');
      final needed =
          referencedFiles(unionTables).difference(onDisk);
      var downloaded = 0;
      if (needed.isNotEmpty) {
        log('正在下载 ${needed.length} 个照片/视频…');
        final req =
            await client.postUrl(u('/union_media'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'have': onDisk.toList()}));
        final resp = await req.close();
        if (resp.statusCode != 200) {
          final body = await utf8.decoder.bind(resp).join();
          throw StateError('下载媒体失败：$body');
        }
        final zipPath = p.join(tempDir.path, 'download.zip');
        final out = File(zipPath).openWrite();
        await out.addStream(resp);
        await out.close();
        final outDir = Directory(p.join(tempDir.path, 'ex'));
        await outDir.create(recursive: true);
        await compute(_unzipTo, {'zip': zipPath, 'out': outDir.path});
        downloaded += await BackupService.instance.moveMediaIn(outDir, 'media');
        downloaded +=
            await BackupService.instance.moveMediaIn(outDir, 'avatars');
      }

      log('同步完成');
      return SyncJoinResult(
          hostName, uploaded, newBabies, newMoments, downloaded);
    } finally {
      client.close(force: true);
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
