import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/date_utils.dart';
import 'database_helper.dart';
import 'models.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// ---------------- 宝宝 ----------------
class BabyRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  Future<List<Baby>> all() async {
    final rows = await (await _db).query('babies', orderBy: 'createdAt ASC');
    return rows.map(Baby.fromMap).toList();
  }

  Future<Baby?> byId(String id) async {
    final rows =
        await (await _db).query('babies', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Baby.fromMap(rows.first);
  }

  Future<void> insert(Baby baby) async =>
      (await _db).insert('babies', baby.toMap());

  Future<void> update(Baby baby) async => (await _db)
      .update('babies', baby.toMap(), where: 'id = ?', whereArgs: [baby.id]);

  /// 删除宝宝及其全部关联数据；返回需要删除的媒体文件名。
  Future<List<String>> delete(String id) async {
    final db = await _db;
    final media = await db.rawQuery(
        'SELECT m.file, m.thumbFile FROM media m JOIN moments r ON m.recordId = r.id WHERE r.babyId = ?',
        [id]);
    await db.transaction((txn) async {
      await txn.delete('media',
          where:
              'recordId IN (SELECT id FROM moments WHERE babyId = ?)',
          whereArgs: [id]);
      await txn.delete('moment_tags',
          where:
              'momentId IN (SELECT id FROM moments WHERE babyId = ?)',
          whereArgs: [id]);
      await txn.delete('moments', where: 'babyId = ?', whereArgs: [id]);
      await txn.delete('growth', where: 'babyId = ?', whereArgs: [id]);
      await txn.delete('milestones', where: 'babyId = ?', whereArgs: [id]);
      await txn.delete('tags', where: 'babyId = ?', whereArgs: [id]);
      await txn.delete('babies', where: 'id = ?', whereArgs: [id]);
    });
    return media
        .expand((m) => [m['file'] as String, m['thumbFile'] as String?])
        .whereType<String>()
        .toList();
  }
}

/// ---------------- 标签 ----------------
class TagRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  Future<List<Tag>> forBaby(String babyId) async {
    final rows = await (await _db)
        .query('tags', where: 'babyId = ?', whereArgs: [babyId], orderBy: 'name');
    return rows.map(Tag.fromMap).toList();
  }

  Future<Tag> ensure(String babyId, String name) async {
    final db = await _db;
    final trimmed = name.trim();
    final rows = await db.query('tags',
        where: 'babyId = ? AND name = ?', whereArgs: [babyId, trimmed]);
    if (rows.isNotEmpty) return Tag.fromMap(rows.first);
    final tag = Tag(id: newId(), babyId: babyId, name: trimmed);
    await db.insert('tags', tag.toMap());
    return tag;
  }

  Future<Map<String, List<Tag>>> forMoments(List<String> momentIds) async {
    if (momentIds.isEmpty) return {};
    final placeholders = List.filled(momentIds.length, '?').join(',');
    final rows = await (await _db).rawQuery(
        'SELECT mt.momentId, t.id, t.babyId, t.name FROM moment_tags mt '
        'JOIN tags t ON t.id = mt.tagId WHERE mt.momentId IN ($placeholders)',
        momentIds);
    final result = <String, List<Tag>>{};
    for (final r in rows) {
      result
          .putIfAbsent(r['momentId'] as String, () => [])
          .add(Tag.fromMap(r));
    }
    return result;
  }

  Future<void> setForMoment(String momentId, List<String> tagIds) async {
    final db = await _db;
    await db
        .delete('moment_tags', where: 'momentId = ?', whereArgs: [momentId]);
    final batch = db.batch();
    for (final t in tagIds) {
      batch.insert('moment_tags', {'momentId': momentId, 'tagId': t});
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteTag(String tagId) async {
    final db = await _db;
    await db.delete('moment_tags', where: 'tagId = ?', whereArgs: [tagId]);
    await db.delete('tags', where: 'id = ?', whereArgs: [tagId]);
  }
}

/// ---------------- 时间轴记录 ----------------
class MomentFilter {
  final String? keyword;
  final bool favoriteOnly;
  final bool withMediaOnly;
  final String? tagId;
  final String? milestoneId;
  final DateTime? from;
  final DateTime? to;

  const MomentFilter({
    this.keyword,
    this.favoriteOnly = false,
    this.withMediaOnly = false,
    this.tagId,
    this.milestoneId,
    this.from,
    this.to,
  });

  MomentFilter copyWith({
    String? Function()? keyword,
    bool? favoriteOnly,
    bool? withMediaOnly,
    String? Function()? tagId,
    String? Function()? milestoneId,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) =>
      MomentFilter(
        keyword: keyword != null ? keyword() : this.keyword,
        favoriteOnly: favoriteOnly ?? this.favoriteOnly,
        withMediaOnly: withMediaOnly ?? this.withMediaOnly,
        tagId: tagId != null ? tagId() : this.tagId,
        milestoneId: milestoneId != null ? milestoneId() : this.milestoneId,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
      );
}

class MomentRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  static const pageSize = 15;

  (String, List<Object?>) _where(String babyId, MomentFilter? f) {
    final clauses = <String>['babyId = ?'];
    final args = <Object?>[babyId];
    if (f != null) {
      if (f.favoriteOnly) clauses.add('isFavorite = 1');
      if (f.milestoneId != null) {
        clauses.add('milestoneId = ?');
        args.add(f.milestoneId);
      }
      if (f.tagId != null) {
        clauses.add(
            'id IN (SELECT momentId FROM moment_tags WHERE tagId = ?)');
        args.add(f.tagId);
      }
      if (f.withMediaOnly) {
        clauses.add('id IN (SELECT recordId FROM media)');
      }
      if (f.from != null) {
        clauses.add('date >= ?');
        args.add(AppDateUtils.toMs(f.from!));
      }
      if (f.to != null) {
        clauses.add('date <= ?');
        args.add(AppDateUtils.toMs(f.to!));
      }
      final kw = f.keyword?.trim();
      if (kw != null && kw.isNotEmpty) {
        clauses.add('content LIKE ?');
        args.add('%$kw%');
      }
    }
    return (clauses.join(' AND '), args);
  }

  Future<List<Moment>> query(
    String babyId, {
    MomentFilter? filter,
    int limit = pageSize,
    int offset = 0,
    String orderBy = 'date DESC, createdAt DESC',
  }) async {
    final (where, args) = _where(babyId, filter);
    final rows = await (await _db).query('moments',
        where: where, whereArgs: args, orderBy: orderBy, limit: limit, offset: offset);
    return _attach(rows);
  }

  Future<int> count(String babyId, {MomentFilter? filter}) async {
    final (where, args) = _where(babyId, filter);
    final r = await (await _db).rawQuery(
        'SELECT COUNT(*) AS c FROM moments WHERE $where', args);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<Moment?> byId(String id) async {
    final rows =
        await (await _db).query('moments', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final list = await _attach(rows);
    return list.first;
  }

  Future<List<Moment>> _attach(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return [];
    final db = await _db;
    final ids = rows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final mediaRows = await db.query('media',
        where: 'recordId IN ($placeholders)',
        whereArgs: ids,
        orderBy: 'sortOrder ASC');
    final mediaMap = <String, List<MediaItem>>{};
    for (final m in mediaRows) {
      mediaMap
          .putIfAbsent(m['recordId'] as String, () => [])
          .add(MediaItem.fromMap(m));
    }
    final tagMap = await TagRepository().forMoments(ids);
    return rows
        .map((r) => Moment.fromMap(r,
            media: mediaMap[r['id']] ?? const [], tags: tagMap[r['id']] ?? const []))
        .toList();
  }

  Future<List<Moment>> recent(String babyId, int limit) =>
      query(babyId, limit: limit);

  /// 往年今日：与 [date] 同月同日但不同年份的记录（SQL 下推，避免全表扫描）。
  Future<List<Moment>> onThisDay(String babyId, DateTime date) async {
    final mmdd =
        '${AppDateUtils.two(date.month)}-${AppDateUtils.two(date.day)}';
    final rows = await (await _db).rawQuery(
        "SELECT * FROM moments WHERE babyId = ? "
        "AND strftime('%m-%d', date / 1000, 'unixepoch', 'localtime') = ? "
        "AND strftime('%Y', date / 1000, 'unixepoch', 'localtime') != ? "
        'ORDER BY date DESC',
        [babyId, mmdd, date.year.toString()]);
    return _attach(rows);
  }

  /// 某个月内有记录的日期集合。
  Future<Set<int>> daysWithMoments(String babyId, int year, int month) async {
    final start = DateTime(year, month, 1, 12);
    final end = DateTime(year, month + 1, 1, 12);
    final rows = await (await _db).query('moments',
        columns: ['date'],
        where: 'babyId = ? AND date >= ? AND date < ?',
        whereArgs: [babyId, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch]);
    return rows
        .map((r) =>
            DateTime.fromMillisecondsSinceEpoch((r['date'] as int?) ?? 0).day)
        .toSet();
  }

  /// 当前宝宝最近一张照片（用于首页头图）。
  Future<MediaItem?> latestImage(String babyId) async {
    final rows = await (await _db).rawQuery(
        'SELECT m.* FROM media m JOIN moments r ON m.recordId = r.id '
        "WHERE r.babyId = ? AND m.type = 'image' "
        'ORDER BY r.date DESC, m.sortOrder ASC LIMIT 1',
        [babyId]);
    return rows.isEmpty ? null : MediaItem.fromMap(rows.first);
  }

  Future<(int, int)> mediaCounts(String babyId) async {
    final rows = await (await _db).rawQuery(
        'SELECT m.type AS t, COUNT(*) AS c FROM media m '
        'JOIN moments r ON m.recordId = r.id WHERE r.babyId = ? GROUP BY m.type',
        [babyId]);
    var images = 0, videos = 0;
    for (final r in rows) {
      if (r['t'] == 'video') {
        videos = (r['c'] as int?) ?? 0;
      } else {
        images = (r['c'] as int?) ?? 0;
      }
    }
    return (images, videos);
  }

  Future<void> insert(Moment moment, List<MediaItem> media,
      List<String> tagIds, DatabaseExecutor? executor) async {
    Future<void> run(DatabaseExecutor db) async {
      await db.insert('moments', moment.toMap());
      for (final m in media) {
        await db.insert('media', m.toMap());
      }
      for (final t in tagIds) {
        await db.insert('moment_tags', {'momentId': moment.id, 'tagId': t});
      }
    }

    if (executor != null) return run(executor);
    final db = await _db;
    await db.transaction((txn) async => run(txn));
  }

  Future<void> update(Moment moment, List<MediaItem> media,
      List<String> tagIds) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('moments', moment.toMap(),
          where: 'id = ?', whereArgs: [moment.id]);
      await txn
          .delete('media', where: 'recordId = ?', whereArgs: [moment.id]);
      for (final m in media) {
        await txn.insert('media', m.toMap());
      }
      await txn.delete('moment_tags',
          where: 'momentId = ?', whereArgs: [moment.id]);
      for (final t in tagIds) {
        await txn
            .insert('moment_tags', {'momentId': moment.id, 'tagId': t});
      }
    });
  }

  /// 删除记录；返回需要删除的媒体文件名。
  Future<List<String>> delete(String id) async {
    final db = await _db;
    final media = await db.query('media', where: 'recordId = ?', whereArgs: [id]);
    await db.transaction((txn) async {
      await txn.delete('media', where: 'recordId = ?', whereArgs: [id]);
      await txn.delete('moment_tags', where: 'momentId = ?', whereArgs: [id]);
      await txn.delete('moments', where: 'id = ?', whereArgs: [id]);
    });
    return media
        .expand((m) => [m['file'] as String, m['thumbFile'] as String?])
        .whereType<String>()
        .toList();
  }
}

/// ---------------- 成长数据 ----------------
class GrowthRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  Future<List<GrowthEntry>> list(String babyId) async {
    final rows = await (await _db).query('growth',
        where: 'babyId = ?', whereArgs: [babyId], orderBy: 'date ASC');
    return rows.map(GrowthEntry.fromMap).toList();
  }

  Future<GrowthEntry?> latest(String babyId) async {
    final rows = await (await _db).query('growth',
        where: 'babyId = ?',
        whereArgs: [babyId],
        orderBy: 'date DESC',
        limit: 1);
    return rows.isEmpty ? null : GrowthEntry.fromMap(rows.first);
  }

  Future<void> insert(GrowthEntry e) async =>
      (await _db).insert('growth', e.toMap());

  Future<void> update(GrowthEntry e) async => (await _db)
      .update('growth', e.toMap(), where: 'id = ?', whereArgs: [e.id]);

  Future<void> delete(String id) async =>
      (await _db).delete('growth', where: 'id = ?', whereArgs: [id]);
}

/// ---------------- 里程碑 ----------------
class MilestoneRepository {
  Future<Database> get _db async => DatabaseHelper.instance.db;

  Future<List<Milestone>> list(String babyId) async {
    final rows = await (await _db).query('milestones',
        where: 'babyId = ?', whereArgs: [babyId], orderBy: 'date DESC');
    return rows.map(Milestone.fromMap).toList();
  }

  Future<Milestone?> byId(String id) async {
    final rows = await (await _db)
        .query('milestones', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Milestone.fromMap(rows.first);
  }

  Future<void> insert(Milestone m) async =>
      (await _db).insert('milestones', m.toMap());

  Future<void> update(Milestone m) async => (await _db)
      .update('milestones', m.toMap(), where: 'id = ?', whereArgs: [m.id]);

  /// 删除里程碑；关联记录解除关联而不删除。
  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('moments', {'milestoneId': null},
          where: 'milestoneId = ?', whereArgs: [id]);
      await txn.delete('milestones', where: 'id = ?', whereArgs: [id]);
    });
  }
}
