import 'package:baby_record/services/daily_album_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyScene', () {
    test('选择置信度最高的已知场景', () {
      expect(
        classifyScene(const [
          SceneSignal('Park', 0.72),
          SceneSignal('Birthday cake', 0.91),
        ]),
        '生日',
      );
    });

    test('可识别常见户外场景', () {
      expect(
        classifyScene(const [SceneSignal('Grass', 0.83)]),
        '户外',
      );
    });

    test('不确定时使用中性文案', () {
      expect(
        classifyScene(const [SceneSignal('Unknown object', 0.99)]),
        '成长瞬间',
      );
    });
  });
}
