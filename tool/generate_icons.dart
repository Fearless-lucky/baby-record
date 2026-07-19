// 启动图标生成脚本：dart run tool/generate_icons.dart
// 从 assets/icon/app_icon.png 生成各密度启动器图标与自适应图标。
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/icon/app_icon.png').readAsBytesSync());
  if (src == null) {
    stderr.writeln('无法解码图标源文件');
    exit(1);
  }

  // 1. 裁剪出圆角方形主体（跳过外围白边）。
  final cropped = _cropRoundedSquare(src);

  // 2. 取主体左上角的奶油色作为底色。
  final bg = cropped.getPixel(4, 4);
  final bgColor = img.ColorRgb8(bg.r.toInt(), bg.g.toInt(), bg.b.toInt());

  // 3. 传统图标：奶油色全铺底 + 主体满幅。
  const legacySizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final e in legacySizes.entries) {
    final canvas = img.Image(width: e.value, height: e.value);
    img.fill(canvas, color: bgColor);
    final art = img.copyResize(cropped,
        width: e.value,
        height: e.value,
        interpolation: img.Interpolation.cubic);
    img.compositeImage(canvas, art, center: true);
    _write('android/app/src/main/res/mipmap-${e.key}/ic_launcher.png', canvas);
  }

  // 4. 自适应图标前景：主体缩到 72% 居中（保证在安全区内）。
  const fgSizes = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
  };
  for (final e in fgSizes.entries) {
    final canvas = img.Image(width: e.value, height: e.value);
    final artSize = (e.value * 0.72).round();
    final art = img.copyResize(cropped,
        width: artSize,
        height: artSize,
        interpolation: img.Interpolation.cubic);
    img.compositeImage(canvas, art, center: true);
    _write(
        'android/app/src/main/res/mipmap-${e.key}/ic_launcher_foreground.png',
        canvas);
  }

  stdout.writeln('图标生成完成');
}

img.Image _cropRoundedSquare(img.Image src) {
  // 源图的圆角方形主体居中，约占中央 84%；按比例裁掉外围白边。
  const margin = 0.078;
  final mx = (src.width * margin).round();
  final my = (src.height * margin).round();
  final side = min(src.width - 2 * mx, src.height - 2 * my);
  final cx = src.width ~/ 2;
  final cy = src.height ~/ 2;
  return img.copyCrop(src,
      x: cx - side ~/ 2, y: cy - side ~/ 2, width: side, height: side);
}

void _write(String path, img.Image image) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
  stdout.writeln('  $path');
}
