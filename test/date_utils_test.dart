import 'package:baby_record/core/utils/date_utils.dart';
import 'package:baby_record/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDateUtils', () {
    test('dayOfLife：出生当天为第 1 天', () {
      final birth = DateTime(2024, 1, 1, 8, 30);
      expect(AppDateUtils.dayOfLife(birth, DateTime(2024, 1, 1)), 1);
      expect(AppDateUtils.dayOfLife(birth, DateTime(2024, 1, 31)), 31);
      expect(AppDateUtils.dayOfLife(birth, DateTime(2025, 1, 1)), 367);
    });

    test('ageParts 正确计算年月日', () {
      final birth = DateTime(2023, 6, 15, 10);
      var p = AppDateUtils.ageParts(birth, DateTime(2024, 8, 20));
      expect((p.years, p.months, p.days), (1, 2, 5));

      // 日不够减，向前借位
      p = AppDateUtils.ageParts(birth, DateTime(2024, 8, 10));
      expect((p.years, p.months, p.days), (1, 1, 26));

      // 月不够减，向年借位
      p = AppDateUtils.ageParts(birth, DateTime(2024, 3, 20));
      expect((p.years, p.months, p.days), (0, 9, 5));
    });

    test('ageText 输出简洁文案', () {
      final birth = DateTime(2023, 1, 10, 9);
      expect(AppDateUtils.ageText(birth, DateTime(2024, 1, 10)), '1岁');
      expect(AppDateUtils.ageText(birth, DateTime(2024, 3, 15)), '1岁2个月');
      expect(AppDateUtils.ageText(birth, DateTime(2023, 2, 10)), '1个月');
      expect(AppDateUtils.ageText(birth, DateTime(2023, 1, 25)), '15天');
    });

    test('sameMonthDay 用于往年今日', () {
      expect(
          AppDateUtils.sameMonthDay(
              DateTime(2023, 6, 1), DateTime(2025, 6, 1)),
          isTrue);
      expect(
          AppDateUtils.sameMonthDay(
              DateTime(2023, 6, 2), DateTime(2025, 6, 1)),
          isFalse);
    });

    test('格式化输出', () {
      final d = DateTime(2024, 3, 5);
      expect(AppDateUtils.full(d), '2024年3月5日');
      expect(AppDateUtils.monthDay(d), '3月5日');
      expect(AppDateUtils.yearMonth(d), '2024年3月');
      expect(AppDateUtils.weekday(d), '周二'); // 2024-03-05 是周二
    });
  });

  group('Models', () {
    test('Moment 序列化往返', () {
      final m = Moment(
        id: 'a',
        babyId: 'b',
        date: DateTime(2024, 5, 1, 12),
        content: '今天会笑了',
        isFavorite: true,
        milestoneId: null,
        createdAt: DateTime(2024, 5, 1, 20),
        updatedAt: DateTime(2024, 5, 2, 9),
      );
      final restored = Moment.fromMap(m.toMap());
      expect(restored.id, 'a');
      expect(restored.content, '今天会笑了');
      expect(restored.isFavorite, isTrue);
      expect(restored.date.millisecondsSinceEpoch,
          m.date.millisecondsSinceEpoch);
    });

    test('GrowthEntry 序列化往返', () {
      final e = GrowthEntry(
        id: 'g',
        babyId: 'b',
        date: DateTime(2024, 1, 1, 12),
        heightCm: 50.5,
        weightKg: 3.25,
        headCm: null,
      );
      final restored = GrowthEntry.fromMap(e.toMap());
      expect(restored.heightCm, 50.5);
      expect(restored.weightKg, 3.25);
      expect(restored.headCm, isNull);
      expect(restored.isEmpty, isFalse);
    });

    test('Baby 序列化往返', () {
      final b = Baby(
        id: 'x',
        name: '小明',
        nickname: '豆豆',
        birthDate: DateTime(2024, 2, 29, 12),
        avatarFile: null,
        createdAt: DateTime(2024, 3, 1),
      );
      final restored = Baby.fromMap(b.toMap());
      expect(restored.displayName, '豆豆');
      expect(restored.birthDate.millisecondsSinceEpoch,
          b.birthDate.millisecondsSinceEpoch);
    });

    test('Milestone 预置图标均有定义', () {
      for (final preset in kMilestonePresets) {
        expect(kMilestoneIcons.containsKey(preset.$2), isTrue,
            reason: preset.$2);
      }
    });
  });
}
