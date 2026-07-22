import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:photo_manager/photo_manager.dart';

class AlbumPermissionDenied implements Exception {
  const AlbumPermissionDenied();
}

class SceneSignal {
  final String label;
  final double confidence;

  const SceneSignal(this.label, this.confidence);
}

class DailyAlbumCandidate {
  final AssetEntity asset;
  final Uint8List thumbnail;
  final DateTime capturedAt;
  final bool? hasFace;
  final String scene;

  const DailyAlbumCandidate({
    required this.asset,
    required this.thumbnail,
    required this.capturedAt,
    this.hasFace,
    this.scene = '成长瞬间',
  });

  DailyAlbumCandidate copyWith({bool? hasFace, String? scene}) =>
      DailyAlbumCandidate(
        asset: asset,
        thumbnail: thumbnail,
        capturedAt: capturedAt,
        hasFace: hasFace ?? this.hasFace,
        scene: scene ?? this.scene,
      );
}

class DailyAlbumBatch {
  final List<DailyAlbumCandidate> candidates;
  final int totalCount;

  const DailyAlbumBatch(this.candidates, this.totalCount);
}

/// 按拍摄日期读取相册，并在设备端做人脸检测与大致场景分类。
class DailyAlbumService {
  static const defaultLimit = 60;

  /// 截图与聊天工具保存的图片/表情包不参与推荐（按相册目录名过滤）。
  static const _blockedDirs = [
    'screenshot',
    '截图',
    'screen_shot',
    'weixin',
    'wechat',
    'tencent/micromsg',
    'pictures/qq',
    'qq_images',
    'qq收藏',
    'emoji',
    '表情',
  ];

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.08,
    ),
  );
  final ImageLabeler _imageLabeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.5),
  );

  static bool _isBlocked(AssetEntity asset) {
    final dir = (asset.relativePath ?? '').toLowerCase();
    if (dir.isEmpty) return false;
    return _blockedDirs.any(dir.contains);
  }

  Future<DailyAlbumBatch> loadForDay(DateTime day, {int limit = defaultLimit}) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) throw const AlbumPermissionDenied();

    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        createTimeCond: DateTimeCond(min: start, max: end),
      ),
    );
    if (albums.isEmpty) return const DailyAlbumBatch([], 0);

    final total = await albums.first.assetCountAsync;
    if (total == 0) return const DailyAlbumBatch([], 0);
    var assets =
        (await albums.first.getAssetListRange(
          start: 0,
          end: total,
          type: RequestType.image,
        )).toList();

    // 过滤截图/聊天图片，并按（尺寸+拍摄秒）去掉连拍重复项。
    assets = assets.where((a) => !_isBlocked(a)).toList();
    final seen = <String>{};
    assets = assets.where((a) {
      final key =
          '${a.width}x${a.height}_${a.createDateTime.millisecondsSinceEpoch ~/ 1000}';
      return seen.add(key);
    }).toList();
    assets.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
    final filteredTotal = assets.length;
    if (limit > 0 && assets.length > limit) {
      assets = assets.sublist(0, limit);
    }

    final candidates = <DailyAlbumCandidate>[];
    for (final asset in assets) {
      final thumbnail = await asset.thumbnailDataWithSize(
        const ThumbnailSize.square(320),
        quality: 82,
      );
      if (thumbnail == null) continue;
      candidates.add(
        DailyAlbumCandidate(
          asset: asset,
          thumbnail: thumbnail,
          capturedAt: asset.createDateTime,
        ),
      );
    }
    // totalCount 返回过滤后的数量，避免与展示数量对不上。
    return DailyAlbumBatch(candidates, filteredTotal);
  }

  Future<DailyAlbumCandidate> analyze(DailyAlbumCandidate candidate) async {
    final file = await candidate.asset.file;
    if (file == null) return candidate.copyWith(hasFace: false);
    final input = InputImage.fromFilePath(file.path);
    final faces = await _faceDetector.processImage(input);
    final labels = await _imageLabeler.processImage(input);
    return candidate.copyWith(
      hasFace: faces.isNotEmpty,
      scene: classifyScene(
        labels.map((label) => SceneSignal(label.label, label.confidence)),
      ),
    );
  }

  static Future<void> openSettings() => PhotoManager.openSetting();

  Future<void> dispose() async {
    await _faceDetector.close();
    await _imageLabeler.close();
  }
}

String classifyScene(Iterable<SceneSignal> signals) {
  const categories = <String, List<String>>{
    '生日': ['birthday', 'cake', 'party', 'candle', '生日', '蛋糕', '聚会'],
    '吃饭': [
      'food',
      'meal',
      'dish',
      'cuisine',
      'fruit',
      'tableware',
      'restaurant',
      '食物',
      '水果',
      '餐厅',
    ],
    '玩耍': ['playground', 'toy', 'game', 'ball', 'swing', '玩具', '游戏', '球'],
    '戏水': ['beach', 'sea', 'ocean', 'swimming', 'pool', '海滩', '游泳', '泳池'],
    '旅行': [
      'landmark',
      'mountain',
      'airplane',
      'aircraft',
      'train',
      'tourism',
      '飞机',
      '火车',
      '旅游',
    ],
    '户外': [
      'outdoor',
      'sky',
      'grass',
      'park',
      'tree',
      'plant',
      'nature',
      'garden',
      '天空',
      '草地',
      '公园',
      '树',
    ],
    '萌宠': ['animal', 'pet', 'dog', 'cat', '动物', '宠物', '狗', '猫'],
    '居家': ['room', 'furniture', 'bed', 'indoor', 'house', '室内', '房间', '家具'],
  };

  var result = '成长瞬间';
  var bestScore = 0.0;
  for (final signal in signals) {
    final label = signal.label.toLowerCase();
    for (final entry in categories.entries) {
      if (entry.value.any(label.contains) && signal.confidence > bestScore) {
        result = entry.key;
        bestScore = signal.confidence;
      }
    }
  }
  return result;
}
