import 'dart:io';

import 'package:flutter/material.dart';

import '../core/utils/date_utils.dart';

/// ---------------- 宝宝档案 ----------------
class Baby {
  final String id;
  final String name;
  final String nickname;
  final DateTime birthDate;

  /// 头像文件名（相对存储，位于 avatars 目录）。
  final String? avatarFile;

  /// 首页自定义头图文件名（位于 avatars 目录）；为空时使用最新照片。
  final String? headerFile;
  final DateTime createdAt;

  const Baby({
    required this.id,
    required this.name,
    required this.nickname,
    required this.birthDate,
    this.avatarFile,
    this.headerFile,
    required this.createdAt,
  });

  String get displayName => nickname.isNotEmpty ? nickname : name;

  String ageText([DateTime? on]) =>
      AppDateUtils.ageText(birthDate, AppDateUtils.day(on ?? DateTime.now()));

  int dayOfLife([DateTime? on]) =>
      AppDateUtils.dayOfLife(birthDate, AppDateUtils.day(on ?? DateTime.now()));

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'nickname': nickname,
        'birthDate': birthDate.millisecondsSinceEpoch,
        'avatarFile': avatarFile,
        'headerFile': headerFile,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Baby.fromMap(Map<String, Object?> m) => Baby(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        nickname: (m['nickname'] as String?) ?? '',
        birthDate:
            DateTime.fromMillisecondsSinceEpoch((m['birthDate'] as int?) ?? 0),
        avatarFile: m['avatarFile'] as String?,
        headerFile: m['headerFile'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as int?) ?? 0),
      );

  Baby copyWith({
    String? name,
    String? nickname,
    DateTime? birthDate,
    String? Function()? avatarFile,
    String? Function()? headerFile,
  }) =>
      Baby(
        id: id,
        name: name ?? this.name,
        nickname: nickname ?? this.nickname,
        birthDate: birthDate ?? this.birthDate,
        avatarFile: avatarFile != null ? avatarFile() : this.avatarFile,
        headerFile: headerFile != null ? headerFile() : this.headerFile,
        createdAt: createdAt,
      );
}

/// ---------------- 媒体 ----------------
enum MediaType { image, video }

MediaType mediaTypeFromString(String? s) =>
    s == 'video' ? MediaType.video : MediaType.image;

String mediaTypeToString(MediaType t) =>
    t == MediaType.video ? 'video' : 'image';

class MediaItem {
  final String id;
  final String recordId;
  final MediaType type;

  /// 原始文件名（相对存储，位于 media 目录）。
  final String file;

  /// 缩略图文件名；为空时回退到原图。
  final String? thumbFile;
  final int width;
  final int height;
  final int sortOrder;

  const MediaItem({
    required this.id,
    required this.recordId,
    required this.type,
    required this.file,
    this.thumbFile,
    this.width = 0,
    this.height = 0,
    this.sortOrder = 0,
  });

  double get aspectRatio =>
      (width > 0 && height > 0) ? width / height : 4 / 3;

  Map<String, Object?> toMap() => {
        'id': id,
        'recordId': recordId,
        'type': mediaTypeToString(type),
        'file': file,
        'thumbFile': thumbFile,
        'width': width,
        'height': height,
        'sortOrder': sortOrder,
      };

  factory MediaItem.fromMap(Map<String, Object?> m) => MediaItem(
        id: m['id'] as String,
        recordId: (m['recordId'] as String?) ?? '',
        type: mediaTypeFromString(m['type'] as String?),
        file: m['file'] as String,
        thumbFile: m['thumbFile'] as String?,
        width: (m['width'] as int?) ?? 0,
        height: (m['height'] as int?) ?? 0,
        sortOrder: (m['sortOrder'] as int?) ?? 0,
      );
}

/// ---------------- 标签 ----------------
class Tag {
  final String id;
  final String babyId;
  final String name;

  const Tag({required this.id, required this.babyId, required this.name});

  Map<String, Object?> toMap() => {'id': id, 'babyId': babyId, 'name': name};

  factory Tag.fromMap(Map<String, Object?> m) => Tag(
        id: m['id'] as String,
        babyId: (m['babyId'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
      );
}

/// ---------------- 成长记录（时间轴条目） ----------------
class Moment {
  final String id;
  final String babyId;
  final DateTime date;
  final String content;
  final bool isFavorite;
  final String? milestoneId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 查询时填充，不入库。
  final List<MediaItem> media;
  final List<Tag> tags;

  const Moment({
    required this.id,
    required this.babyId,
    required this.date,
    this.content = '',
    this.isFavorite = false,
    this.milestoneId,
    required this.createdAt,
    required this.updatedAt,
    this.media = const [],
    this.tags = const [],
  });

  bool get hasMedia => media.isNotEmpty;

  MediaItem? get cover => media.isEmpty ? null : media.first;

  Map<String, Object?> toMap() => {
        'id': id,
        'babyId': babyId,
        'date': date.millisecondsSinceEpoch,
        'content': content,
        'isFavorite': isFavorite ? 1 : 0,
        'milestoneId': milestoneId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory Moment.fromMap(
    Map<String, Object?> m, {
    List<MediaItem> media = const [],
    List<Tag> tags = const [],
  }) =>
      Moment(
        id: m['id'] as String,
        babyId: (m['babyId'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as int?) ?? 0),
        content: (m['content'] as String?) ?? '',
        isFavorite: ((m['isFavorite'] as int?) ?? 0) == 1,
        milestoneId: m['milestoneId'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as int?) ?? 0),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch((m['updatedAt'] as int?) ?? 0),
        media: media,
        tags: tags,
      );

  Moment copyWith({
    DateTime? date,
    String? content,
    bool? isFavorite,
    String? Function()? milestoneId,
    DateTime? updatedAt,
    List<MediaItem>? media,
    List<Tag>? tags,
  }) =>
      Moment(
        id: id,
        babyId: babyId,
        date: date ?? this.date,
        content: content ?? this.content,
        isFavorite: isFavorite ?? this.isFavorite,
        milestoneId: milestoneId != null ? milestoneId() : this.milestoneId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        media: media ?? this.media,
        tags: tags ?? this.tags,
      );
}

/// ---------------- 成长数据 ----------------
class GrowthEntry {
  final String id;
  final String babyId;
  final DateTime date;
  final double? heightCm;
  final double? weightKg;
  final double? headCm;
  final String note;

  const GrowthEntry({
    required this.id,
    required this.babyId,
    required this.date,
    this.heightCm,
    this.weightKg,
    this.headCm,
    this.note = '',
  });

  bool get isEmpty => heightCm == null && weightKg == null && headCm == null;

  double? valueOf(GrowthMetric m) => switch (m) {
        GrowthMetric.height => heightCm,
        GrowthMetric.weight => weightKg,
        GrowthMetric.head => headCm,
      };

  Map<String, Object?> toMap() => {
        'id': id,
        'babyId': babyId,
        'date': date.millisecondsSinceEpoch,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'headCm': headCm,
        'note': note,
      };

  factory GrowthEntry.fromMap(Map<String, Object?> m) => GrowthEntry(
        id: m['id'] as String,
        babyId: (m['babyId'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as int?) ?? 0),
        heightCm: (m['heightCm'] as num?)?.toDouble(),
        weightKg: (m['weightKg'] as num?)?.toDouble(),
        headCm: (m['headCm'] as num?)?.toDouble(),
        note: (m['note'] as String?) ?? '',
      );
}

enum GrowthMetric { height, weight, head }

extension GrowthMetricInfo on GrowthMetric {
  String get label => switch (this) {
        GrowthMetric.height => '身高',
        GrowthMetric.weight => '体重',
        GrowthMetric.head => '头围',
      };

  String get unit => switch (this) {
        GrowthMetric.height => 'cm',
        GrowthMetric.weight => 'kg',
        GrowthMetric.head => 'cm',
      };

  IconData get icon => switch (this) {
        GrowthMetric.height => Icons.straighten_rounded,
        GrowthMetric.weight => Icons.monitor_weight_outlined,
        GrowthMetric.head => Icons.face_outlined,
      };

  String format(double? v) {
    if (v == null) return '—';
    return switch (this) {
      GrowthMetric.weight => v.toStringAsFixed(2),
      _ => v.toStringAsFixed(1),
    };
  }
}

/// ---------------- 里程碑 ----------------
class Milestone {
  final String id;
  final String babyId;
  final String title;

  /// 预置图标 key，见 [kMilestoneIcons]。
  final String iconKey;
  final DateTime date;
  final String note;
  final DateTime createdAt;

  const Milestone({
    required this.id,
    required this.babyId,
    required this.title,
    required this.iconKey,
    required this.date,
    this.note = '',
    required this.createdAt,
  });

  IconData get icon => kMilestoneIcons[iconKey] ?? Icons.star_rounded;

  Map<String, Object?> toMap() => {
        'id': id,
        'babyId': babyId,
        'title': title,
        'iconKey': iconKey,
        'date': date.millisecondsSinceEpoch,
        'note': note,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Milestone.fromMap(Map<String, Object?> m) => Milestone(
        id: m['id'] as String,
        babyId: (m['babyId'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        iconKey: (m['iconKey'] as String?) ?? 'custom',
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as int?) ?? 0),
        note: (m['note'] as String?) ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as int?) ?? 0),
      );
}

/// 预置里程碑模板（标题 + 图标）。
const kMilestonePresets = <(String, String)>[
  ('第一次抬头', 'head_up'),
  ('第一次翻身', 'roll'),
  ('第一次独坐', 'sit'),
  ('第一次爬行', 'crawl'),
  ('第一次站立', 'stand'),
  ('第一次走路', 'walk'),
  ('第一颗乳牙', 'tooth'),
  ('第一次叫妈妈', 'talk'),
  ('第一次叫爸爸', 'talk'),
  ('第一次旅行', 'travel'),
  ('第一次游泳', 'swim'),
  ('第一次理发', 'haircut'),
  ('第一次生日', 'birthday'),
  ('第一次添加辅食', 'food'),
];

const kMilestoneIcons = <String, IconData>{
  'head_up': Icons.child_care_rounded,
  'roll': Icons.autorenew_rounded,
  'sit': Icons.airline_seat_recline_normal_rounded,
  'crawl': Icons.pets_rounded,
  'stand': Icons.accessibility_new_rounded,
  'walk': Icons.directions_walk_rounded,
  'tooth': Icons.sentiment_satisfied_alt_rounded,
  'talk': Icons.record_voice_over_rounded,
  'travel': Icons.flight_rounded,
  'swim': Icons.pool_rounded,
  'haircut': Icons.content_cut_rounded,
  'birthday': Icons.cake_rounded,
  'food': Icons.restaurant_rounded,
  'custom': Icons.star_rounded,
};

/// ---------------- 通用 ----------------
class StorageStats {
  final int mediaBytes;
  final int databaseBytes;
  final int avatarBytes;
  final int momentCount;
  final int imageCount;
  final int videoCount;

  const StorageStats({
    required this.mediaBytes,
    required this.databaseBytes,
    required this.avatarBytes,
    required this.momentCount,
    required this.imageCount,
    required this.videoCount,
  });

  int get totalBytes => mediaBytes + databaseBytes + avatarBytes;

  String get totalText {
    final b = totalBytes;
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }
}

/// 文件存在性工具（避免到处 import dart:io 的地方再写判断）。
bool fileExists(String path) => File(path).existsSync();
