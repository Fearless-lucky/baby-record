import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';

/// 成长月报：按月汇总照片、里程碑与成长变化，可导出长图分享。
class MonthlyReportPage extends StatefulWidget {
  const MonthlyReportPage({super.key});

  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _ReportData {
  List<Moment> moments = [];
  List<Milestone> milestones = [];
  GrowthEntry? growthFirst;
  GrowthEntry? growthLast;
  int photoCount = 0;
  int videoCount = 0;
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  late DateTime _month;
  _ReportData _data = _ReportData();
  bool _loading = true;
  final _captureKey = GlobalKey();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // 默认显示上个月（内容更完整）；如果上个月没有数据会在界面提示切换。
    final now = DateTime.now();
    _month = DateTime(now.year, now.month - 1, 1, 12);
    _load();
  }

  Future<void> _load() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    setState(() => _loading = true);
    final start = AppDateUtils.monthStart(_month);
    final end = AppDateUtils.monthEnd(_month);
    final moments = await MomentRepository().query(baby.id,
        filter: MomentFilter(from: start, to: end),
        limit: 200,
        orderBy: 'date ASC, createdAt ASC');
    final allMilestones = await MilestoneRepository().list(baby.id);
    final growth = await GrowthRepository().list(baby.id);
    final inMonth = growth
        .where((g) => !g.date.isBefore(start) && !g.date.isAfter(end))
        .toList();
    var photos = 0, videos = 0;
    for (final m in moments) {
      for (final item in m.media) {
        item.type == MediaType.video ? videos++ : photos++;
      }
    }
    if (!mounted) return;
    setState(() {
      _data = _ReportData()
        ..moments = moments
        ..milestones = allMilestones
            .where((m) => !m.date.isBefore(start) && !m.date.isAfter(end))
            .toList()
        ..growthFirst = inMonth.isEmpty ? null : inMonth.first
        ..growthLast = inMonth.isEmpty ? null : inMonth.last
        ..photoCount = photos
        ..videoCount = videos;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1, 12));
    _load();
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      // 等待两帧，确保图片解码完成后再截图。
      await Future.delayed(const Duration(milliseconds: 300));
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final name =
          '成长月报_${DateFormat('yyyy年M月').format(_month)}.png';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], subject: name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final baby = context.watch<AppState>().currentBaby;
    return Scaffold(
      appBar: AppBar(
        title: const Text('成长月报'),
        actions: [
          if (!_loading && _data.moments.isNotEmpty)
            TextButton.icon(
              onPressed: _exporting ? null : _export,
              icon: const Icon(Icons.ios_share_rounded, size: 17),
              label: Text(_exporting ? '生成中…' : '导出长图'),
            ),
        ],
      ),
      body: Column(
        children: [
          // 月份切换
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Text(
                    AppDateUtils.yearMonth(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _data.moments.isEmpty && _data.milestones.isEmpty
                    ? const EmptyView(
                        icon: Icons.auto_awesome_outlined,
                        title: '这个月还没有内容',
                        message: '切换到其他月份，或去记录一些美好瞬间吧',
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 48),
                        child: RepaintBoundary(
                          key: _captureKey,
                          child: Container(
                            color: p.scaffold,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            child: _buildReport(p, baby),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(AppPalette p, Baby? baby) {
    final t = Theme.of(context).textTheme;
    final monthEnd = AppDateUtils.monthEnd(_month);
    final photos = _data.moments
        .expand((m) => m.media)
        .where((i) => i.type == MediaType.image)
        .take(9)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // 标题区
        Center(
          child: Column(
            children: [
              Text(AppDateUtils.yearMonth(_month),
                  style: t.displaySmall?.copyWith(fontSize: 30)),
              const SizedBox(height: 6),
              if (baby != null)
                Text(
                  '${baby.displayName} · ${baby.ageText(monthEnd)}',
                  style: t.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // 照片拼贴
        if (photos.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              children: [
                for (final item in photos)
                  ThumbImage(item.thumbFile ?? item.file, cacheWidth: 400),
              ],
            ),
          ),
        const SizedBox(height: 20),
        // 统计
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.card,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(t, p, '${_data.moments.length}', '条记录'),
              _stat(t, p, '${_data.photoCount}', '张照片'),
              _stat(t, p, '${_data.videoCount}', '个视频'),
              _stat(t, p, '${_data.milestones.length}', '个里程碑'),
            ],
          ),
        ),
        // 成长变化
        if (_data.growthFirst != null && _data.growthLast != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.card,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本月成长', style: t.titleMedium),
                const SizedBox(height: 10),
                for (final metric in GrowthMetric.values)
                  if (_data.growthFirst!.valueOf(metric) != null &&
                      _data.growthLast!.valueOf(metric) != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '${metric.label} ${metric.format(_data.growthFirst!.valueOf(metric))} → ${metric.format(_data.growthLast!.valueOf(metric))} ${metric.unit}'
                        '${_deltaText(metric)}',
                        style: t.bodyMedium,
                      ),
                    ),
              ],
            ),
          ),
        ],
        // 里程碑
        if (_data.milestones.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本月的第一次', style: t.titleMedium),
                const SizedBox(height: 10),
                for (final m in _data.milestones)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(m.icon, size: 18, color: p.accent),
                        const SizedBox(width: 10),
                        Expanded(child: Text(m.title, style: t.bodyMedium)),
                        Text(AppDateUtils.monthDay(m.date),
                            style: t.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        // 精选片段
        if (_data.moments.any((m) => m.content.trim().isNotEmpty)) ...[
          const SizedBox(height: 20),
          Text('这个月的只言片语', style: t.titleMedium),
          const SizedBox(height: 10),
          for (final m in _data.moments
              .where((m) => m.content.trim().isNotEmpty)
              .take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppDateUtils.monthDay(m.date),
                      style: t.labelSmall?.copyWith(color: p.accent)),
                  const SizedBox(height: 3),
                  Text(m.content,
                      style: t.bodyMedium,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Center(
          child: Text('宝宝成长记录 · 仅保存于本机',
              style: t.labelSmall?.copyWith(fontSize: 10)),
        ),
      ],
    );
  }

  String _deltaText(GrowthMetric metric) {
    final d = _data.growthLast!.valueOf(metric)! -
        _data.growthFirst!.valueOf(metric)!;
    if (d == 0) return '';
    return '（${d > 0 ? '+' : ''}${metric.format(d)}）';
  }

  Widget _stat(TextTheme t, AppPalette p, String value, String label) {
    return Column(
      children: [
        Text(value, style: t.displaySmall?.copyWith(fontSize: 26)),
        const SizedBox(height: 4),
        Text(label, style: t.labelSmall),
      ],
    );
  }
}
