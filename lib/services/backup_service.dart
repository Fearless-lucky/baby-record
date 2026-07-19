import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database_helper.dart';
import 'backup_utils.dart';
import 'media_service.dart';

/// 在隔离线程中创建备份压缩包（流式写入，避免大量照片占用内存）。
Future<void> _createBackupZip(Map<String, Object?> args) async {
  final outPath = args['outPath'] as String;
  final jsonPath = args['jsonPath'] as String;
  final files = (args['files'] as List).cast<Map<String, String>>();
  final encoder = ZipFileEncoder();
  encoder.create(outPath);
  await encoder.addFile(File(jsonPath), 'backup.json');
  for (final f in files) {
    final file = File(f['src']!);
    if (file.existsSync()) {
      await encoder.addFile(file, f['arc']!);
    }
  }
  await encoder.close();
}

/// 在隔离线程中解压备份包。
Future<void> _extractBackupZip(Map<String, String> args) async {
  final archive = ZipDecoder().decodeStream(InputFileStream(args['zip']!));
  await extractArchiveToDisk(archive, args['out']!);
}

/// 在隔离线程中加密文件（AES-256-CBC，密钥 = SHA256(密码)，前 16 字节为 IV）。
Future<void> _encryptFile(Map<String, String> args) async {
  final src = File(args['src']!);
  final dest = File(args['dest']!);
  final key = enc.Key(Uint8List.fromList(
      sha256.convert(utf8.encode(args['password']!)).bytes));
  final iv = enc.IV.fromSecureRandom(16);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final encrypted = encrypter.encryptBytes(src.readAsBytesSync(), iv: iv);
  await dest.writeAsBytes([...iv.bytes, ...encrypted.bytes], flush: true);
}

/// 在隔离线程中解密文件。
Future<void> _decryptFile(Map<String, String> args) async {
  final bytes = File(args['src']!).readAsBytesSync();
  if (bytes.length < 17) throw const FormatException('加密备份文件损坏');
  final key = enc.Key(Uint8List.fromList(
      sha256.convert(utf8.encode(args['password']!)).bytes));
  final iv = enc.IV(Uint8List.fromList(bytes.sublist(0, 16)));
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final decrypted =
      encrypter.decryptBytes(enc.Encrypted(Uint8List.fromList(bytes.sublist(16))), iv: iv);
  await File(args['dest']!).writeAsBytes(decrypted, flush: true);
}

class RestoreSummary {
  final int babies;
  final int moments;
  final int mediaFiles;

  const RestoreSummary(this.babies, this.moments, this.mediaFiles);
}

class MergeSummary {
  final int newBabies;
  final int newMoments;
  final int newMedia;

  const MergeSummary(this.newBabies, this.newMoments, this.newMedia);
}

/// 备份 / 恢复 / 家庭共享：数据 + 所有媒体原文件。
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const encryptedExt = '.babybak';

  /// 创建备份，返回文件路径。[password] 非空时生成加密备份。
  Future<String> createBackup(
      {String? password, void Function(String step)? onProgress}) async {
    onProgress?.call('正在收集数据…');
    final db = await DatabaseHelper.instance.db;
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in kBackupTables) {
      tables[t] = await db.query(t);
    }
    final manifest = {
      'app': 'baby_record',
      'formatVersion': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'tables': tables,
    };

    final base = await getApplicationDocumentsDirectory();
    final tempDir = Directory(p.join(base.path, 'backup_tmp'));
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    await tempDir.create(recursive: true);
    final jsonFile = File(p.join(tempDir.path, 'backup.json'));
    await jsonFile.writeAsString(jsonEncode(manifest), flush: true);

    onProgress?.call('正在整理媒体文件…');
    final files = <Map<String, String>>[];
    final mediaDir = await MediaService.instance.mediaDir();
    await for (final e in mediaDir.list()) {
      if (e is File) {
        files.add({'src': e.path, 'arc': 'media/${p.basename(e.path)}'});
      }
    }
    final avatarDir = await MediaService.instance.avatarDir();
    await for (final e in avatarDir.list()) {
      if (e is File) {
        files.add({'src': e.path, 'arc': 'avatars/${p.basename(e.path)}'});
      }
    }

    onProgress?.call('正在压缩（大文件需要一些时间）…');
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final zipPath = p.join(tempDir.path, 'backup.zip');
    await compute(_createBackupZip, {
      'outPath': zipPath,
      'jsonPath': jsonFile.path,
      'files': files,
    });

    final encrypting = password != null && password.isNotEmpty;
    String outPath;
    if (encrypting) {
      onProgress?.call('正在加密…');
      outPath = p.join((await MediaService.instance.backupDir()).path,
          '宝宝成长备份_$stamp$encryptedExt');
      await compute(_encryptFile,
          {'src': zipPath, 'dest': outPath, 'password': password});
    } else {
      outPath = p.join((await MediaService.instance.backupDir()).path,
          '宝宝成长备份_$stamp.zip');
      await File(zipPath).copy(outPath);
    }

    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
    return outPath;
  }

  /// 分享备份/共享包到微信/网盘/文件管理器等。
  Future<void> shareBackup(String path) async {
    await Share.shareXFiles([XFile(path)], subject: '宝宝成长记录备份');
  }

  /// 选择备份文件（支持 .zip 与加密的 .babybak），必要时请求密码。
  /// 返回 (zip 路径, 临时目录)；调用方负责清理。用户取消返回 null。
  Future<(String, Directory)?> _pickAndDecrypt({
    required Future<String?> Function() askPassword,
    void Function(String step)? onProgress,
  }) async {
    final picked = await FilePicker.platform.pickFiles();
    var path = picked?.files.single.path;
    if (path == null) return null;

    final base = await getApplicationDocumentsDirectory();
    final tempDir = Directory(p.join(base.path,
        'restore_tmp_${DateTime.now().millisecondsSinceEpoch}'));
    await tempDir.create(recursive: true);

    if (path.endsWith(encryptedExt)) {
      final password = await askPassword();
      if (password == null || password.isEmpty) {
        await tempDir.delete(recursive: true);
        return null;
      }
      onProgress?.call('正在解密…');
      final zipPath = p.join(tempDir.path, 'decrypted.zip');
      try {
        await compute(_decryptFile,
            {'src': path, 'dest': zipPath, 'password': password});
      } catch (_) {
        await tempDir.delete(recursive: true);
        throw const FormatException('解密失败：密码不正确或文件已损坏');
      }
      path = zipPath;
    }
    return (path, tempDir);
  }

  Future<Map<String, dynamic>> _readManifest(Directory tempDir) async {
    final jsonFile = File(p.join(tempDir.path, 'backup.json'));
    if (!jsonFile.existsSync()) {
      throw const FormatException('备份文件不完整：缺少 backup.json');
    }
    final manifest =
        jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
    final error = validateBackupManifest(manifest);
    if (error != null) throw FormatException(error);
    return manifest;
  }

  Future<int> _moveMediaIn(Directory tempDir, String sub) async {
    final srcDir = Directory(p.join(tempDir.path, sub));
    if (!srcDir.existsSync()) return 0;
    final target = sub == 'media'
        ? await MediaService.instance.mediaDir()
        : await MediaService.instance.avatarDir();
    var count = 0;
    await for (final e in srcDir.list()) {
      if (e is File) {
        final dest = p.join(target.path, p.basename(e.path));
        try {
          await e.rename(dest);
        } catch (_) {
          await e.copy(dest);
          await e.delete();
        }
        count++;
      }
    }
    return count;
  }

  /// 删除目标目录中未被引用的文件，返回释放的字节数。
  Future<int> _deleteUnreferenced(
      Directory dir, Set<String> referenced, String prefix) async {
    var freed = 0;
    if (!dir.existsSync()) return 0;
    await for (final e in dir.list()) {
      if (e is File && !referenced.contains('$prefix${p.basename(e.path)}')) {
        try {
          freed += await e.length();
          await e.delete();
        } catch (_) {}
      }
    }
    return freed;
  }

  /// 从备份恢复全部数据。返回恢复摘要；用户取消时返回 null。
  ///
  /// 安全顺序：先完整校验 → 移入媒体文件（不删旧文件）→ 单事务替换数据库 →
  /// 最后清理未被引用的孤儿文件。任何一步失败都不会留下"数据库指向不存在文件"的状态。
  Future<RestoreSummary?> restoreBackup({
    required Future<String?> Function() askPassword,
    void Function(String step)? onProgress,
  }) async {
    final picked = await _pickAndDecrypt(
        askPassword: askPassword, onProgress: onProgress);
    if (picked == null) return null;
    final (zipPath, tempDir) = picked;

    try {
      onProgress?.call('正在解压备份…');
      await compute(
          _extractBackupZip, {'zip': zipPath, 'out': tempDir.path});

      onProgress?.call('正在校验数据…');
      final manifest = await _readManifest(tempDir);
      final tables = manifest['tables'] as Map<String, dynamic>;

      onProgress?.call('正在恢复照片与视频…');
      final mediaCount = await _moveMediaIn(tempDir, 'media');
      await _moveMediaIn(tempDir, 'avatars');

      onProgress?.call('正在写入数据…');
      final db = await DatabaseHelper.instance.db;
      await db.transaction((txn) async {
        for (final t in kBackupTables) {
          await txn.delete(t);
        }
        for (final t in kBackupTables) {
          for (final row in (tables[t] as List)) {
            if (row is Map) {
              await txn.insert(t, row.map((k, v) => MapEntry(k.toString(), v)));
            }
          }
        }
      });

      onProgress?.call('正在清理…');
      final referenced = referencedFiles(tables);
      await _deleteUnreferenced(
          await MediaService.instance.mediaDir(), referenced, 'media/');
      await _deleteUnreferenced(
          await MediaService.instance.avatarDir(), referenced, 'avatars/');

      return RestoreSummary((tables['babies'] as List).length,
          (tables['moments'] as List).length, mediaCount);
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 家庭共享：导入共享包并**合并**（不删除现有数据）。
  /// 记录以 UUID 为主键，重复内容自动跳过；返回新增数量摘要。
  Future<MergeSummary?> importAndMerge({
    required Future<String?> Function() askPassword,
    void Function(String step)? onProgress,
  }) async {
    final picked = await _pickAndDecrypt(
        askPassword: askPassword, onProgress: onProgress);
    if (picked == null) return null;
    final (zipPath, tempDir) = picked;

    try {
      onProgress?.call('正在解压共享包…');
      await compute(
          _extractBackupZip, {'zip': zipPath, 'out': tempDir.path});

      onProgress?.call('正在校验数据…');
      final manifest = await _readManifest(tempDir);
      final tables = manifest['tables'] as Map<String, dynamic>;

      onProgress?.call('正在合并媒体文件…');
      final newMedia = await _moveMediaIn(tempDir, 'media');
      await _moveMediaIn(tempDir, 'avatars');

      onProgress?.call('正在合并数据…');
      final db = await DatabaseHelper.instance.db;
      var newBabies = 0;
      var newMoments = 0;
      await db.transaction((txn) async {
        for (final t in kBackupTables) {
          for (final row in (tables[t] as List)) {
            if (row is! Map) continue;
            final map = row.map((k, v) => MapEntry(k.toString(), v));
            final result = await txn.insert(t, map,
                conflictAlgorithm: ConflictAlgorithm.ignore);
            if (result != 0) {
              if (t == 'babies') newBabies++;
              if (t == 'moments') newMoments++;
            }
          }
        }
      });

      return MergeSummary(newBabies, newMoments, newMedia);
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
