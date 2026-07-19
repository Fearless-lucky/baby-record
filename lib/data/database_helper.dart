import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 数据库单例。所有数据保存在手机本地。
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'baby_record.db';

  /// 数据库版本。
  /// v1: 初始版本。
  /// v2: babies 增加 headerFile 列（首页自定义头图）。
  /// v3: moments / milestones / growth 增加 author 列（WiFi 同步的作者标记）。
  static const _version = 3;

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<String> get databasePath async =>
      p.join(await getDatabasesPath(), _dbName);

  Future<Database> _open() async {
    final path = await databasePath;
    return openDatabase(
      path,
      version: _version,
      onUpgrade: (db, oldVersion, newVersion) async {
        // 逐版本迁移；新增变更时在下方追加分支并将 _version 加一。
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE babies ADD COLUMN headerFile TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE moments ADD COLUMN author TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE milestones ADD COLUMN author TEXT NOT NULL DEFAULT ''");
          await db.execute(
              "ALTER TABLE growth ADD COLUMN author TEXT NOT NULL DEFAULT ''");
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE babies(
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  nickname TEXT NOT NULL DEFAULT '',
  birthDate INTEGER NOT NULL,
  avatarFile TEXT,
  headerFile TEXT,
  createdAt INTEGER NOT NULL
)''');
        await db.execute('''
CREATE TABLE moments(
  id TEXT PRIMARY KEY,
  babyId TEXT NOT NULL,
  date INTEGER NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  isFavorite INTEGER NOT NULL DEFAULT 0,
  milestoneId TEXT,
  createdAt INTEGER NOT NULL,
  updatedAt INTEGER NOT NULL,
  author TEXT NOT NULL DEFAULT ''
)''');
        await db.execute(
            'CREATE INDEX idx_moments_baby_date ON moments(babyId, date DESC)');
        await db.execute('''
CREATE TABLE media(
  id TEXT PRIMARY KEY,
  recordId TEXT NOT NULL,
  type TEXT NOT NULL,
  file TEXT NOT NULL,
  thumbFile TEXT,
  width INTEGER NOT NULL DEFAULT 0,
  height INTEGER NOT NULL DEFAULT 0,
  sortOrder INTEGER NOT NULL DEFAULT 0
)''');
        await db.execute(
            'CREATE INDEX idx_media_record ON media(recordId, sortOrder)');
        await db.execute('''
CREATE TABLE tags(
  id TEXT PRIMARY KEY,
  babyId TEXT NOT NULL,
  name TEXT NOT NULL,
  UNIQUE(babyId, name)
)''');
        await db.execute('''
CREATE TABLE moment_tags(
  momentId TEXT NOT NULL,
  tagId TEXT NOT NULL,
  PRIMARY KEY(momentId, tagId)
)''');
        await db.execute(
            'CREATE INDEX idx_moment_tags_tag ON moment_tags(tagId)');
        await db.execute('''
CREATE TABLE growth(
  id TEXT PRIMARY KEY,
  babyId TEXT NOT NULL,
  date INTEGER NOT NULL,
  heightCm REAL,
  weightKg REAL,
  headCm REAL,
  note TEXT NOT NULL DEFAULT '',
  author TEXT NOT NULL DEFAULT ''
)''');
        await db.execute(
            'CREATE INDEX idx_growth_baby_date ON growth(babyId, date)');
        await db.execute('''
CREATE TABLE milestones(
  id TEXT PRIMARY KEY,
  babyId TEXT NOT NULL,
  title TEXT NOT NULL,
  iconKey TEXT NOT NULL DEFAULT 'custom',
  date INTEGER NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  createdAt INTEGER NOT NULL,
  author TEXT NOT NULL DEFAULT ''
)''');
        await db.execute(
            'CREATE INDEX idx_milestones_baby ON milestones(babyId, date DESC)');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
