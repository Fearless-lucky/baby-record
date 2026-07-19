/// 备份相关的纯函数，便于单元测试。
library;

const kBackupTables = [
  'babies',
  'moments',
  'media',
  'tags',
  'moment_tags',
  'growth',
  'milestones',
];

/// 校验备份清单结构。合法返回 null，否则返回错误描述。
String? validateBackupManifest(Map<String, dynamic> manifest) {
  if (manifest['app'] != 'baby_record') {
    return '不是有效的宝宝成长记录备份';
  }
  final tables = manifest['tables'];
  if (tables is! Map<String, dynamic>) {
    return '备份文件不完整：缺少数据表';
  }
  for (final t in kBackupTables) {
    if (tables[t] is! List) return '备份文件不完整：缺少 $t 表';
  }
  return null;
}

/// 计算备份/数据库中被引用的媒体与头像文件名集合。
Set<String> referencedFiles(Map<String, dynamic> tables) {
  final files = <String>{};
  final media = tables['media'];
  if (media is List) {
    for (final m in media) {
      if (m is Map) {
        final f = m['file'];
        final t = m['thumbFile'];
        if (f is String) files.add('media/$f');
        if (t is String) files.add('media/$t');
      }
    }
  }
  final babies = tables['babies'];
  if (babies is List) {
    for (final b in babies) {
      if (b is Map) {
        final a = b['avatarFile'];
        final h = b['headerFile'];
        if (a is String) files.add('avatars/$a');
        if (h is String) files.add('avatars/$h');
      }
    }
  }
  return files;
}
