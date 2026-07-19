import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/media_service.dart';
import '../../theme/app_theme.dart';

/// 缩略图：带加载占位与错误兜底。
class ThumbImage extends StatelessWidget {
  final String fileName;
  final BoxFit fit;
  final int cacheWidth;
  final double? width;
  final double? height;

  const ThumbImage(
    this.fileName, {
    super.key,
    this.fit = BoxFit.cover,
    this.cacheWidth = 720,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = MediaPaths.mediaBase;
    if (base == null) return _placeholder(p);
    return Image.file(
      File(MediaPaths.media(fileName)),
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _placeholder(p),
      frameBuilder: (context, child, frame, wasSync) {
        if (wasSync || frame != null) return child;
        return _placeholder(p);
      },
    );
  }

  Widget _placeholder(AppPalette p) => Container(
        width: width,
        height: height,
        color: p.accentSoft.withValues(alpha: 0.5),
        child: Icon(Icons.image_outlined, color: p.subInk, size: 28),
      );
}

/// 视频角标。
class VideoBadge extends StatelessWidget {
  final double size;
  const VideoBadge({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.play_arrow_rounded,
          color: Colors.white, size: 20),
    );
  }
}

/// 宝宝头像。
class BabyAvatar extends StatelessWidget {
  final String? avatarFile;
  final String name;
  final double radius;

  const BabyAvatar({
    super.key,
    required this.avatarFile,
    required this.name,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasAvatar = avatarFile != null && MediaPaths.avatarBase != null;
    return CircleAvatar(
      radius: radius,
      backgroundColor: p.accentSoft,
      backgroundImage:
          hasAvatar ? FileImage(File(MediaPaths.avatar(avatarFile!))) : null,
      child: hasAvatar
          ? null
          : Text(
              name.isEmpty ? '宝' : name.characters.first,
              style: TextStyle(
                  color: p.accent,
                  fontSize: radius * 0.85,
                  fontWeight: FontWeight.w600),
            ),
    );
  }
}

/// 空状态。
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: p.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: p.accent),
            ),
            const SizedBox(height: 20),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  style: t.bodySmall, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误状态。
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.error_outline_rounded,
      title: '出了点问题',
      message: message,
      actionLabel: '重试',
      onAction: onRetry,
    );
  }
}

/// 区块标题。
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  const SectionHeader(this.title, {super.key, this.actionText, this.onAction});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: t.headlineMedium?.copyWith(fontSize: 19)),
          ),
          if (actionText != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionText!,
                  style: TextStyle(color: p.accent, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

/// 删除等危险操作的确认框。
Future<bool> confirmDanger(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '删除',
}) async {
  final p = context.palette;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: p.favorite),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 带进度的模态任务执行器（备份/恢复/保存媒体时使用）。
Future<T?> runWithProgress<T>(
  BuildContext context, {
  required Future<T> Function(void Function(String step) report) task,
}) async {
  final step = ValueNotifier<String>('请稍候…');
  final dialogFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(width: 18),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: step,
                builder: (_, s, __) => Text(s, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  T? result;
  Object? error;
  try {
    result = await task((s) => step.value = s);
  } catch (e) {
    error = e;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await dialogFuture.catchError((_) {});
  if (error != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：$error')));
    }
    return null;
  }
  return result;
}

/// 收藏心形按钮（带轻量弹性动画）。
class FavoriteButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  final double size;

  const FavoriteButton({
    super.key,
    required this.active,
    required this.onTap,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: active ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: size,
            color: active ? p.favorite : p.subInk,
          ),
        ),
      ),
    );
  }
}
