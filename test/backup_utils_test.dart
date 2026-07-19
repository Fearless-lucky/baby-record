import 'package:baby_record/services/backup_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> validManifest() => {
        'app': 'baby_record',
        'formatVersion': 2,
        'tables': {
          'babies': [
            {'id': 'b1', 'avatarFile': 'a.jpg', 'headerFile': 'h.jpg'}
          ],
          'moments': [],
          'media': [
            {'file': '1.jpg', 'thumbFile': '1_thumb.jpg'},
            {'file': '2.mp4', 'thumbFile': null},
          ],
          'tags': [],
          'moment_tags': [],
          'growth': [],
          'milestones': [],
        },
      };

  group('validateBackupManifest', () {
    test('合法清单返回 null', () {
      expect(validateBackupManifest(validManifest()), isNull);
    });

    test('app 标识错误被拒绝', () {
      final m = validManifest()..['app'] = 'other';
      expect(validateBackupManifest(m), isNotNull);
    });

    test('缺少任一表被拒绝（防止清空后才发现不完整）', () {
      for (final table in kBackupTables) {
        final m = validManifest();
        (m['tables'] as Map).remove(table);
        expect(validateBackupManifest(m), isNotNull, reason: table);
      }
    });

    test('表不是列表被拒绝', () {
      final m = validManifest();
      final tables = Map<String, dynamic>.from(m['tables'] as Map);
      tables['growth'] = 'broken';
      m['tables'] = tables;
      expect(validateBackupManifest(m), isNotNull);
    });

    test('tables 缺失被拒绝', () {
      final m = validManifest()..remove('tables');
      expect(validateBackupManifest(m), isNotNull);
    });
  });

  group('filterRowForTable', () {
    test('未知列被丢弃，已知列保留', () {
      final row = filterRowForTable('moments', {
        'id': 'm1',
        'babyId': 'b1',
        'content': 'hi',
        'author': '妈妈',
        'futureColumn': '应被丢弃',
      });
      expect(row['id'], 'm1');
      expect(row['author'], '妈妈');
      expect(row.containsKey('futureColumn'), isFalse);
    });

    test('缺失列不出现（由数据库默认值补齐）', () {
      final row = filterRowForTable('moments', {'id': 'm1'});
      expect(row.containsKey('author'), isFalse);
      expect(row.containsKey('content'), isFalse);
    });

    test('备份涉及的全部表都有列定义', () {
      for (final t in kBackupTables) {
        expect(kTableColumns.containsKey(t), isTrue, reason: t);
      }
    });
  });

  group('referencedFiles', () {
    test('收集媒体与头像引用', () {
      final files = referencedFiles(
          validManifest()['tables'] as Map<String, dynamic>);
      expect(
          files,
          containsAll([
            'media/1.jpg',
            'media/1_thumb.jpg',
            'media/2.mp4',
            'avatars/a.jpg',
            'avatars/h.jpg',
          ]));
      expect(files.length, 5);
    });

    test('空表返回空集合', () {
      expect(referencedFiles({}), isEmpty);
    });
  });
}
