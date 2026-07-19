import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/media_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';
import 'edit_record_page.dart';
import 'video_player_page.dart';

/// 记录详情：沉浸式媒体 + 故事排版。
class RecordDetailPage extends StatefulWidget {
  final String momentId;

  /// 与来源卡片一致的 Hero tag；为空则不启用 Hero 转场。
  final String? heroTag;

  const RecordDetailPage({super.key, required this.momentId, this.heroTag});

  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  Moment? _moment;
  Milestone? _milestone;
  bool _notFound = false;
  int _page = 0;
  final _pageController = PageController();
  int _loadedVersion = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = context.watch<AppState>().version;
    if (v != _loadedVersion) {
      _loadedVersion = v;
      _load();
    }
  }

  Future<void> _load() async {
    final m = await MomentRepository().byId(widget.momentId);
    Milestone? ms;
    if (m?.milestoneId != null) {
      ms = await MilestoneRepository().byId(m!.milestoneId!);
    }
    if (!mounted) return;
    setState(() {
      _moment = m;
      _milestone = ms;
      _notFound = m == null;
      if (_page >= (m?.media.length ?? 1)) _page = 0;
    });
  }

  Future<void> _toggleFavorite() async {
    final m = _moment;
    if (m == null) return;
    final updated = m.copyWith(
        isFavorite: !m.isFavorite, updatedAt: DateTime.now());
    await MomentRepository().update(updated, updated.media,
        updated.tags.map((t) => t.id).toList());
    if (mounted) context.read<AppState>().bumpData();
  }

  Future<void> _delete() async {
    final ok = await confirmDanger(
      context,
      title: '删除这条记录？',
      message: '记录中的照片与视频文件也会一并删除，且不可恢复。',
    );
    if (!ok || !mounted) return;
    final files = await MomentRepository().delete(widget.momentId);
    await MediaService.instance.deleteMediaFiles(files);
    if (!mounted) return;
    context.read<AppState>().bumpData();
    Navigator.pop(context);
  }

  Future<void> _edit() async {
    final m = _moment;
    if (m == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditRecordPage(existing: m)),
    );
  }

  void _playVideo(MediaItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          filePath: MediaPaths.media(item.file),
          title: AppDateUtils.full(_moment?.date ?? DateTime.now()),
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final m = _moment;

    if (_notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(
          icon: Icons.search_off_rounded,
          title: '记录不存在',
          message: '它可能已经被删除',
        ),
      );
    }
    if (m == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    final baby = context.read<AppState>().currentBaby;
    final hasMedia = m.media.isNotEmpty;

    return Scaffold(
      backgroundColor: p.scaffold,
      body: Column(
        children: [
          if (hasMedia)
            AspectRatio(
              aspectRatio: 0.92,
              child: widget.heroTag != null
                  ? Hero(
                      tag: widget.heroTag!,
                      child: _buildGallery(m, p),
                    )
                  : _buildGallery(m, p),
            )
          else
            _buildNoMediaHeader(p),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppDateUtils.full(m.date),
                      style: t.displaySmall?.copyWith(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(
                    baby == null
                        ? AppDateUtils.weekday(m.date)
                        : '${AppDateUtils.weekday(m.date)} · ${baby.ageText(m.date)} · 第${baby.dayOfLife(m.date)}天',
                    style: t.bodySmall,
                  ),
                  if (_milestone != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.accentSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_milestone!.icon, size: 18, color: p.accent),
                          const SizedBox(width: 8),
                          Text(_milestone!.title,
                              style: t.titleMedium
                                  ?.copyWith(color: p.accent, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                  if (m.content.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(m.content, style: t.bodyLarge),
                  ],
                  if (m.tags.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in m.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: p.card,
                              border: Border.all(color: p.line),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('# ${tag.name}',
                                style: t.bodySmall
                                    ?.copyWith(color: p.ink, fontSize: 12)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text(
                        '记录于 ${AppDateUtils.full(m.createdAt)}',
                        style: t.labelSmall,
                      ),
                      if (m.author.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        AuthorChip(m.author),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overlayButton(Widget child, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    );
  }

  Widget _buildGallery(Moment m, AppPalette p) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoViewGallery.builder(
            pageController: _pageController,
            itemCount: m.media.length,
            onPageChanged: (i) => setState(() => _page = i),
            backgroundDecoration:
                const BoxDecoration(color: Colors.black),
            builder: (context, i) {
              final item = m.media[i];
              if (item.type == MediaType.image) {
                return PhotoViewGalleryPageOptions(
                  imageProvider:
                      FileImage(File(MediaPaths.media(item.file))),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3.5,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white54, size: 48),
                  ),
                );
              }
              return PhotoViewGalleryPageOptions.customChild(
                child: GestureDetector(
                  onTap: () => _playVideo(item),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.thumbFile != null)
                        ThumbImage(item.thumbFile!, fit: BoxFit.contain)
                      else
                        Container(color: Colors.black),
                      const Center(child: VideoBadge(size: 64)),
                    ],
                  ),
                ),
              );
            },
            loadingBuilder: (_, __) => const Center(
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
          ),
          // 顶部操作区
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      _overlayButton(
                        const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                        () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      _overlayButton(
                        Icon(
                          m.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color:
                              m.isFavorite ? const Color(0xFFFF7A6E) : Colors.white,
                          size: 19,
                        ),
                        _toggleFavorite,
                      ),
                      const SizedBox(width: 10),
                      _overlayButton(
                        const Icon(Icons.edit_outlined,
                            color: Colors.white, size: 18),
                        _edit,
                      ),
                      const SizedBox(width: 10),
                      _overlayButton(
                        const Icon(Icons.delete_outline_rounded,
                            color: Colors.white, size: 19),
                        _delete,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (m.media.length > 1)
            Positioned(
              bottom: 14,
              right: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_page + 1} / ${m.media.length}',
                  style:
                      const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoMediaHeader(AppPalette p) {
    return Container(
      width: double.infinity,
      color: p.accentSoft,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: p.ink, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
              FavoriteButton(
                  active: _moment!.isFavorite, onTap: _toggleFavorite),
              IconButton(
                icon: Icon(Icons.edit_outlined, color: p.ink),
                onPressed: _edit,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: p.ink),
                onPressed: _delete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
