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

/// 各表当前版本的全部列名：恢复/合并时按此过滤，
/// 保证旧备份（缺列）与新备份（多列）都能安全写入当前数据库。
const kTableColumns = <String, List<String>>{
  'babies': [
    'id', 'name', 'nickname', 'birthDate', 'avatarFile', 'headerFile',
    'createdAt',
  ],
  'moments': [
    'id', 'babyId', 'date', 'content', 'isFavorite', 'milestoneId',
    'createdAt', 'updatedAt', 'author',
  ],
  'media': [
    'id', 'recordId', 'type', 'file', 'thumbFile', 'width', 'height',
    'sortOrder',
  ],
  'tags': ['id', 'babyId', 'name'],
  'moment_tags': ['momentId', 'tagId'],
  'growth': [
    'id', 'babyId', 'date', 'heightCm', 'weightKg', 'headCm', 'note',
    'author',
  ],
  'milestones': [
    'id', 'babyId', 'title', 'iconKey', 'date', 'note', 'createdAt',
    'author',
  ],
};

/// 只保留当前版本已知的列；未知列丢弃，缺失列由数据库默认值补齐。
Map<String, Object?> filterRowForTable(String table, Map row) {
  final columns = kTableColumns[table];
  if (columns == null) return {};
  final result = <String, Object?>{};
  for (final c in columns) {
    if (row.containsKey(c)) result[c] = row[c];
  }
  return result;
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
