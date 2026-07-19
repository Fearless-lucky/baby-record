import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/media_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../calendar/calendar_page.dart';
import '../common/widgets.dart';
import '../record/edit_record_page.dart';
import '../record/record_detail_page.dart';
import '../search/search_page.dart';
import '../settings/baby_edit_page.dart';
import 'favorites_page.dart';
import 'memories_page.dart';
import 'monthly_report_page.dart';

class HomePage extends StatefulWidget {
  final void Function(int index) onJumpToTab;
  const HomePage({super.key, required this.onJumpToTab});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomeData {
  MediaItem? latestPhoto;
  List<Moment> recent = [];
  List<Moment> onThisDay = [];
  GrowthEntry? latestGrowth;
  int totalMoments = 0;
}

class _HomePageState extends State<HomePage> {
  _HomeData _data = _HomeData();
  bool _loading = true;
  int _loadedVersion = -1;
  String? _loadedBabyId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (state.version != _loadedVersion ||
        state.currentBaby?.id != _loadedBabyId) {
      _loadedVersion = state.version;
      _loadedBabyId = state.currentBaby?.id;
      _load();
    }
  }

  Future<void> _load() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final repo = MomentRepository();
      // 并行加载，减少首屏等待。
      final (latestPhoto, recent, onThisDay, latestGrowth, total) = await (
        repo.latestImage(baby.id),
        repo.recent(baby.id, 8),
        repo.onThisDay(baby.id, DateTime.now()),
        GrowthRepository().latest(baby.id),
        repo.count(baby.id),
      ).wait;
      if (!mounted) return;
      setState(() {
        _data = _HomeData()
          ..latestPhoto = latestPhoto
          ..recent = recent
          ..onThisDay = onThisDay
          ..latestGrowth = latestGrowth
          ..totalMoments = total;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchBaby() async {
    final state = context.read<AppState>();
    final p = context.palette;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in state.babies)
              ListTile(
                leading:
                    BabyAvatar(avatarFile: b.avatarFile, name: b.displayName),
                title: Text(b.displayName),
                subtitle: Text(AppDateUtils.full(b.birthDate)),
                trailing: b.id == state.currentBaby?.id
                    ? Icon(Icons.check_circle_rounded, color: p.accent)
                    : null,
                onTap: () {
                  state.setCurrentBaby(b.id);
                  Navigator.pop(ctx);
                },
              ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.add_circle_outline_rounded, color: p.accent),
              title: const Text('添加宝宝'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const BabyEditPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baby = context.watch<AppState>().currentBaby;
    final p = context.palette;
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return Scaffold(
      body: RefreshIndicator(
        color: p.accent,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(baby, p)),
            SliverToBoxAdapter(child: _buildFeatureRow(p)),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(60),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else ...[
              if (_data.onThisDay.isNotEmpty)
                SliverToBoxAdapter(child: _fadeIn(_buildOnThisDayCard(p))),
              if (_data.latestGrowth != null)
                SliverToBoxAdapter(child: _fadeIn(_buildGrowthCard(p))),
              if (_data.recent.isNotEmpty)
                SliverToBoxAdapter(child: _fadeIn(_buildRecent(p, baby))),
              if (_data.totalMoments == 0 && _data.latestGrowth == null)
                SliverToBoxAdapter(child: _buildWelcome(p)),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fadeIn(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      builder: (_, v, c) => Opacity(
          opacity: v, child: Transform.translate(
              offset: Offset(0, 10 * (1 - v)), child: c)),
      child: child,
    );
  }

  Widget _buildHeader(Baby baby, AppPalette p) {
    final t = Theme.of(context).textTheme;
    final width = MediaQuery.of(context).size.width;
    final hasCustomHeader =
        baby.headerFile != null && MediaPaths.avatarBase != null;
    final latestPhoto = _data.latestPhoto;
    final latestExcerpt = _data.recent
        .where((m) => m.content.trim().isNotEmpty)
        .map((m) => m.content.trim().split('\n').first)
        .firstOrNull;

    Widget background;
    if (hasCustomHeader) {
      background = Image.file(
        File(MediaPaths.avatar(baby.headerFile!)),
        fit: BoxFit.cover,
        cacheWidth: 1400,
        errorBuilder: (_, __, ___) => _headerPlaceholder(p),
      );
    } else if (latestPhoto != null) {
      background = ThumbImage(latestPhoto.file, cacheWidth: 1200);
    } else {
      background = _headerPlaceholder(p);
    }

    return SizedBox(
      height: width * 1.08,
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          // 底部渐隐到背景色（照片与下方内容自然过渡）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: width * 0.62,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    p.scaffold.withValues(alpha: 0.45),
                    p.scaffold.withValues(alpha: 0.92),
                    p.scaffold,
                  ],
                  stops: const [0.0, 0.45, 0.82, 1.0],
                ),
              ),
            ),
          ),
          // 顶部遮罩 + 操作
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
                    Colors.black.withValues(
                        alpha: (hasCustomHeader || latestPhoto != null)
                            ? 0.3
                            : 0.0),
                    Colors.transparent
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _switchBaby,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2),
                          ),
                          child: BabyAvatar(
                              avatarFile: baby.avatarFile,
                              name: baby.displayName),
                        ),
                      ),
                      const Spacer(),
                      _glassButton(
                          Icons.search_rounded,
                          () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SearchPage()))),
                      const SizedBox(width: 10),
                      _glassButton(
                          Icons.calendar_month_outlined,
                          () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const CalendarPage()))),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 名字、年龄与一句记录摘要
          Positioned(
            left: 24,
            right: 24,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baby.displayName,
                    style: t.displayLarge?.copyWith(fontSize: 38)),
                const SizedBox(height: 6),
                Text(
                  '${baby.ageText()} · 来到世界第 ${baby.dayOfLife()} 天',
                  style: t.bodyMedium?.copyWith(color: p.subInk),
                ),
                if (latestExcerpt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    latestExcerpt,
                    style: t.bodySmall?.copyWith(
                        color: p.subInk, fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerPlaceholder(AppPalette p) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.accentSoft, p.card],
        ),
      ),
      child: Center(
        child: Icon(Icons.child_care_rounded,
            size: 120, color: p.accent.withValues(alpha: 0.35)),
      ),
    );
  }

  Widget _glassButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }

  /// 三个功能入口：去年今天 / 成长月报 / 我的收藏。
  Widget _buildFeatureRow(AppPalette p) {
    final items = [
      (
        Icons.history_rounded,
        '去年今天',
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MemoriesPage())),
      ),
      (
        Icons.auto_stories_outlined,
        '成长月报',
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MonthlyReportPage())),
      ),
      (
        Icons.favorite_outline_rounded,
        '我的收藏',
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const FavoritesPage())),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          for (final (icon, label, action) in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Material(
                  color: p.card,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: action,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: p.line),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          Icon(icon, color: p.accent, size: 24),
                          const SizedBox(height: 8),
                          Text(label,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 突出的"去年今天"对比卡。
  Widget _buildOnThisDayCard(AppPalette p) {
    final t = Theme.of(context).textTheme;
    final m = _data.onThisDay.first;
    final years = DateTime.now().year - m.date.year;
    final baby = context.read<AppState>().currentBaby;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('往年今日'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            color: p.card,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MemoriesPage())),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: p.line),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.cover != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(22)),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ThumbImage(
                              m.cover!.thumbFile ?? m.cover!.file,
                              cacheWidth: 1000),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$years 年前的今天',
                              style: t.headlineMedium
                                  ?.copyWith(fontSize: 21)),
                          const SizedBox(height: 4),
                          Text(
                            baby == null
                                ? AppDateUtils.full(m.date)
                                : '${AppDateUtils.full(m.date)} · 那时 ${baby.ageText(m.date)}',
                            style: t.bodySmall,
                          ),
                          if (m.content.trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(m.content,
                                style: t.bodyMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                '查看全部 ${_data.onThisDay.length} 段回忆',
                                style: TextStyle(
                                    color: p.accent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 15, color: p.accent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrowthCard(AppPalette p) {
    final t = Theme.of(context).textTheme;
    final g = _data.latestGrowth!;
    Widget metric(GrowthMetric m) => Column(
          children: [
            Text(m.label, style: t.labelSmall),
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                text: m.format(g.valueOf(m)),
                style: t.headlineMedium?.copyWith(fontSize: 22),
                children: [
                  TextSpan(
                      text: ' ${m.unit}',
                      style: t.labelSmall?.copyWith(fontSize: 11)),
                ],
              ),
            ),
          ],
        );
    return Column(
      children: [
        SectionHeader('最新成长',
            actionText: '查看', onAction: () => widget.onJumpToTab(2)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            color: p.card,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: () => widget.onJumpToTab(2),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  border: Border.all(color: p.line),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        metric(GrowthMetric.height),
                        Container(width: 1, height: 44, color: p.line),
                        metric(GrowthMetric.weight),
                        Container(width: 1, height: 44, color: p.line),
                        metric(GrowthMetric.head),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('更新于 ${AppDateUtils.full(g.date)}',
                        style: t.labelSmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecent(AppPalette p, Baby baby) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('最近记录',
            actionText: '全部', onAction: () => widget.onJumpToTab(1)),
        SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _data.recent.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final m = _data.recent[i];
              return GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            RecordDetailPage(momentId: m.id))),
                child: SizedBox(
                  width: 190,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          width: 190,
                          height: 128,
                          child: m.cover != null
                              ? ThumbImage(
                                  m.cover!.thumbFile ?? m.cover!.file,
                                  cacheWidth: 560,
                                )
                              : Container(
                                  color: p.accentSoft,
                                  padding: const EdgeInsets.all(14),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Icon(Icons.format_quote_rounded,
                                        color: p.accent, size: 26),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(AppDateUtils.monthDay(m.date),
                          style: t.titleMedium?.copyWith(fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        m.content.isEmpty
                            ? '${m.media.length} 张照片/视频'
                            : m.content,
                        style: t.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWelcome(AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: EmptyView(
        icon: Icons.auto_stories_outlined,
        title: '从第一张照片开始',
        message: '记录 TA 的每一天：笑容、睡颜、第一次叫妈妈。\n所有数据只保存在这台手机上。',
        actionLabel: '记录此刻',
        onAction: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EditRecordPage())),
      ),
    );
  }
}
