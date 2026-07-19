import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';

/// 时间轴记录卡片：根据照片数量使用杂志式布局。
class RecordCard extends StatelessWidget {
  final Moment moment;
  final Baby? baby;
  final VoidCallback onTap;

  /// 传入后启用封面到详情页的 Hero 转场（同一页面内必须唯一）。
  final String? heroTag;

  /// 水平内边距（时间轴藤蔓布局会调小）。
  final double horizontalPadding;

  const RecordCard({
    super.key,
    required this.moment,
    required this.baby,
    required this.onTap,
    this.heroTag,
    this.horizontalPadding = 20,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final hasText = moment.content.trim().isNotEmpty;

    final mediaWidget = moment.hasMedia
        ? (heroTag != null
            ? Hero(
                tag: heroTag!,
                child: MediaMosaic(media: moment.media),
              )
            : MediaMosaic(media: moment.media))
        : null;

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding, vertical: 7),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mediaWidget != null) ...[
                  mediaWidget,
                  const SizedBox(height: 12),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppDateUtils.monthDay(moment.date),
                              style: t.headlineMedium?.copyWith(fontSize: 19),
                            ),
                          ),
                          if (moment.author.isNotEmpty) ...[
                            AuthorChip(moment.author),
                            const SizedBox(width: 6),
                          ],
                          if (moment.isFavorite)
                            Icon(Icons.favorite_rounded,
                                size: 16, color: p.favorite),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        baby == null
                            ? AppDateUtils.weekday(moment.date)
                            : '${AppDateUtils.weekday(moment.date)} · ${baby!.ageText(moment.date)}',
                        style: t.labelSmall,
                      ),
                      if (hasText) ...[
                        const SizedBox(height: 8),
                        Text(
                          moment.content,
                          style: t.bodyMedium,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (moment.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in moment.tags.take(4))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: p.accentSoft.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('#${tag.name}',
                                    style: t.labelSmall
                                        ?.copyWith(color: p.accent)),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 杂志式照片拼图。
class MediaMosaic extends StatelessWidget {
  final List<MediaItem> media;
  final double borderRadius;

  const MediaMosaic({super.key, required this.media, this.borderRadius = 14});

  @override
  Widget build(BuildContext context) {
    final shown = media.take(4).toList();
    final extra = media.length - shown.length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          switch (shown.length) {
            case 1:
              return _cell(shown[0], w, w / shown[0].aspectRatio.clamp(0.72, 1.6));
            case 2:
              final h = w * 0.62;
              return Row(children: [
                _cell(shown[0], (w - 3) / 2, h),
                const SizedBox(width: 3),
                _cell(shown[1], (w - 3) / 2, h),
              ]);
            case 3:
              final leftW = w * 0.62;
              final rightW = w - leftW - 3;
              final h = leftW * 1.18;
              return Row(children: [
                _cell(shown[0], leftW, h),
                const SizedBox(width: 3),
                Column(children: [
                  _cell(shown[1], rightW, (h - 3) / 2),
                  const SizedBox(height: 3),
                  _cell(shown[2], rightW, (h - 3) / 2),
                ]),
              ]);
            default:
              final cellW = (w - 3) / 2;
              return Column(children: [
                Row(children: [
                  _cell(shown[0], cellW, cellW),
                  const SizedBox(width: 3),
                  _cell(shown[1], cellW, cellW),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  _cell(shown[2], cellW, cellW),
                  const SizedBox(width: 3),
                  _cell(shown[3], cellW, cellW,
                      overlayCount: extra > 0 ? extra : null),
                ]),
              ]);
          }
        },
      ),
    );
  }

  Widget _cell(MediaItem item, double w, double h, {int? overlayCount}) {
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ThumbImage(item.thumbFile ?? item.file,
              cacheWidth: (w * 2).clamp(300, 1400).round()),
          if (item.type == MediaType.video)
            const Center(child: VideoBadge(size: 34)),
          if (overlayCount != null)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Text('+$overlayCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}
