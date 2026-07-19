import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../data/database_helper.dart';
import '../data/models.dart';
import '../data/repositories.dart';

/// 图片缩略图生成（在隔离线程中执行，避免阻塞界面）。
/// 返回 [成功(0/1), 原图宽, 原图高]。
Future<List<int>> _generateThumb(Map<String, String> args) async {
  try {
    final src = File(args['src']!);
    final dest = File(args['dest']!);
    final maxDim = int.parse(args['maxDim'] ?? '720');
    final bytes = await src.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [0, 0, 0];
    final w = decoded.width;
    final h = decoded.height;
    var out = decoded;
    if (w > maxDim || h > maxDim) {
      out = img.copyResize(
        decoded,
        width: w >= h ? maxDim : null,
        height: h > w ? maxDim : null,
        interpolation: img.Interpolation.average,
      );
    }
    await dest.writeAsBytes(img.encodeJpg(out, quality: 85), flush: true);
    return [1, w, h];
  } catch (_) {
    return const [0, 0, 0];
  }
}

/// 媒体路径缓存：启动时初始化一次，之后同步取用，避免列表渲染时频繁异步取路径。
class MediaPaths {
  static String? mediaBase;
  static String? avatarBase;

  static Future<void> ensure() async {
    mediaBase ??= (await MediaService.instance.mediaDir()).path;
    avatarBase ??= (await MediaService.instance.avatarDir()).path;
  }

  /// 目录可能因恢复备份被清空重建，路径本身不变。
  static void reset() {
    mediaBase = null;
    avatarBase = null;
  }

  static String media(String name) => p.join(mediaBase!, name);
  static String avatar(String name) => p.join(avatarBase!, name);
}

/// 节省空间模式：把照片压缩到长边 2048 的 JPEG（原图仍保留在系统相册）。
/// 返回 [成功(0/1), 宽, 高]。
Future<List<int>> _compressImage(Map<String, String> args) async {
  try {
    final src = File(args['src']!);
    final dest = File(args['dest']!);
    final bytes = await src.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [0, 0, 0];
    const maxDim = 2048;
    var out = decoded;
    if (decoded.width > maxDim || decoded.height > maxDim) {
      out = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? maxDim : null,
        height: decoded.height > decoded.width ? maxDim : null,
        interpolation: img.Interpolation.average,
      );
    }
    await dest.writeAsBytes(img.encodeJpg(out, quality: 88), flush: true);
    return [1, out.width, out.height];
  } catch (_) {
    return const [0, 0, 0];
  }
}

/// 本地媒体文件管理：所有照片/视频原文件与缩略图都保存在应用私有目录。
class MediaService {
  MediaService._();
  static final MediaService instance = MediaService._();

  Future<Directory> _base() => getApplicationDocumentsDirectory();

  Future<Directory> mediaDir() async {
    final dir = Directory(p.join((await _base()).path, 'media'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> avatarDir() async {
    final dir = Directory(p.join((await _base()).path, 'avatars'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> backupDir() async {
    final dir = Directory(p.join((await _base()).path, 'backups'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> mediaPath(String fileName) async =>
      p.join((await mediaDir()).path, fileName);

  Future<String> avatarPath(String fileName) async =>
      p.join((await avatarDir()).path, fileName);

  /// 缩略图路径；没有缩略图时返回原文件路径。
  Future<String> thumbPathOf(MediaItem item) =>
      mediaPath(item.thumbFile ?? item.file);

  Future<String> originalPathOf(MediaItem item) => mediaPath(item.file);

  static const _videoExts = {
    '.mp4', '.mov', '.mkv', '.webm', '.avi', '.3gp', '.m4v', '.ts'
  };

  static bool isVideoName(String name) =>
      _videoExts.contains(p.extension(name).toLowerCase());

  /// 导入一个媒体文件：默认保留原始文件并生成缩略图；
  /// [saveSpace] 为 true 时照片以长边 2048 的 JPEG 存储（节省空间）。
  Future<MediaItem> importMedia({
    required String sourcePath,
    required MediaType type,
    required String recordId,
    required int sortOrder,
    bool saveSpace = false,
  }) async {
    final id = newId();
    var ext = p.extension(sourcePath).toLowerCase();
    if (ext.isEmpty) ext = type == MediaType.video ? '.mp4' : '.jpg';
    final dir = await mediaDir();

    String? thumbName;
    var width = 0, height = 0;
    var fileName = '$id$ext';

    if (type == MediaType.image && saveSpace) {
      // 节省空间：直接存储压缩版本。
      final compressed = '$id.jpg';
      final result = await compute(_compressImage, {
        'src': sourcePath,
        'dest': p.join(dir.path, compressed),
      });
      if (result[0] == 1) {
        fileName = compressed;
        width = result[1];
        height = result[2];
      } else {
        await File(sourcePath).copy(p.join(dir.path, fileName));
      }
    } else {
      await File(sourcePath).copy(p.join(dir.path, fileName));
    }
    final destPath = p.join(dir.path, fileName);

    if (type == MediaType.image) {
      thumbName = '${id}_thumb.jpg';
      final result = await compute(_generateThumb, {
        'src': destPath,
        'dest': p.join(dir.path, thumbName),
        'maxDim': '720',
      });
      if (result[0] == 1) {
        if (width == 0) {
          width = result[1];
          height = result[2];
        }
      } else {
        // 无法解码的格式（如 HEIC）：时间轴直接使用原图。
        thumbName = null;
      }
    } else {
      try {
        final thumb = await VideoThumbnail.thumbnailFile(
          video: destPath,
          thumbnailPath: dir.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 720,
          quality: 85,
        );
        if (thumb != null) thumbName = p.basename(thumb);
      } catch (_) {
        thumbName = null;
      }
    }

    return MediaItem(
      id: id,
      recordId: recordId,
      type: type,
      file: fileName,
      thumbFile: thumbName,
      width: width,
      height: height,
      sortOrder: sortOrder,
    );
  }

  /// 导入头像（压缩到合理尺寸以节省空间）。
  Future<String> importAvatar(String sourcePath) =>
      _importSquare(sourcePath, '512');

  /// 导入首页头图（长边 1600，保留较好画质）。
  Future<String> importHeader(String sourcePath) =>
      _importSquare(sourcePath, '1600');

  Future<String> _importSquare(String sourcePath, String maxDim) async {
    final id = newId();
    final dir = await avatarDir();
    final destName = '$id.jpg';
    final result = await compute(_generateThumb, {
      'src': sourcePath,
      'dest': p.join(dir.path, destName),
      'maxDim': maxDim,
    });
    if (result[0] == 1) return destName;
    // 解码失败则原样拷贝。
    final ext = p.extension(sourcePath).toLowerCase();
    final fallback = ext.isEmpty ? '$id.img' : '$id$ext';
    await File(sourcePath).copy(p.join(dir.path, fallback));
    return fallback;
  }

  Future<void> deleteMediaFiles(Iterable<String> fileNames) async {
    final dir = await mediaDir();
    for (final name in fileNames) {
      try {
        final f = File(p.join(dir.path, name));
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> deleteAvatar(String? fileName) async {
    if (fileName == null) return;
    try {
      final f = File(await avatarPath(fileName));
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    if (!dir.existsSync()) return 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// 清理未被数据库引用的媒体/头像文件，返回 (删除数量, 释放字节数)。
  Future<(int, int)> cleanOrphanFiles() async {
    final db = await DatabaseHelper.instance.db;
    final referenced = <String>{};
    for (final m in await db.query('media', columns: ['file', 'thumbFile'])) {
      final f = m['file'] as String?;
      final t = m['thumbFile'] as String?;
      if (f != null) referenced.add('media/$f');
      if (t != null) referenced.add('media/$t');
    }
    for (final b
        in await db.query('babies', columns: ['avatarFile', 'headerFile'])) {
      final a = b['avatarFile'] as String?;
      final h = b['headerFile'] as String?;
      if (a != null) referenced.add('avatars/$a');
      if (h != null) referenced.add('avatars/$h');
    }
    var count = 0, freed = 0;
    Future<void> sweep(Directory dir, String prefix) async {
      if (!dir.existsSync()) return;
      await for (final e in dir.list()) {
        if (e is File &&
            !referenced.contains('$prefix${p.basename(e.path)}')) {
          try {
            freed += await e.length();
            await e.delete();
            count++;
          } catch (_) {}
        }
      }
    }

    await sweep(await mediaDir(), 'media/');
    await sweep(await avatarDir(), 'avatars/');
    return (count, freed);
  }

  Future<StorageStats> stats(String babyId) async {
    final media = await _dirSize(await mediaDir());
    final avatars = await _dirSize(await avatarDir());
    var dbBytes = 0;
    try {
      dbBytes = await File(await DatabaseHelper.instance.databasePath).length();
    } catch (_) {}
    final moments = await MomentRepository().count(babyId);
    final (images, videos) = await MomentRepository().mediaCounts(babyId);
    return StorageStats(
      mediaBytes: media,
      databaseBytes: dbBytes,
      avatarBytes: avatars,
      momentCount: moments,
      imageCount: images,
      videoCount: videos,
    );
  }
}

