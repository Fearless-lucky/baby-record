import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';
import '../milestones/milestones_page.dart';

/// 添加 / 编辑成长数据的底部表单。
Future<void> showGrowthEntrySheet(BuildContext context,
    {GrowthEntry? existing}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _GrowthEntrySheet(existing: existing),
  );
}

class _GrowthEntrySheet extends StatefulWidget {
  final GrowthEntry? existing;
  const _GrowthEntrySheet({this.existing});

  @override
  State<_GrowthEntrySheet> createState() => _GrowthEntrySheetState();
}

class _GrowthEntrySheetState extends State<_GrowthEntrySheet> {
  late DateTime _date;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _head;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = AppDateUtils.day(e?.date ?? DateTime.now());
    _height =
        TextEditingController(text: e?.heightCm?.toStringAsFixed(1) ?? '');
    _weight =
        TextEditingController(text: e?.weightKg?.toStringAsFixed(2) ?? '');
    _head = TextEditingController(text: e?.headCm?.toStringAsFixed(1) ?? '');
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _head.dispose();
    _note.dispose();
    super.dispose();
  }

  double? _parse(String s) => double.tryParse(s.trim());

  Future<void> _save() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    final h = _parse(_height.text);
    final w = _parse(_weight.text);
    final hc = _parse(_head.text);
    if (h == null && w == null && hc == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少填写一项数据')));
      return;
    }
    final repo = GrowthRepository();
    if (widget.existing == null) {
      await repo.insert(GrowthEntry(
        id: newId(),
        babyId: baby.id,
        date: _date,
        heightCm: h,
        weightKg: w,
        headCm: hc,
        note: _note.text.trim(),
      ));
    } else {
      await repo.update(GrowthEntry(
        id: widget.existing!.id,
        babyId: baby.id,
        date: _date,
        heightCm: h,
        weightKg: w,
        headCm: hc,
        note: _note.text.trim(),
      ));
    }
    if (!mounted) return;
    context.read<AppState>().bumpData();
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDanger(context,
        title: '删除这条数据？', message: '该成长数据将被删除。');
    if (!ok) return;
    await GrowthRepository().delete(widget.existing!.id);
    if (!mounted) return;
    context.read<AppState>().bumpData();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.existing == null ? '添加成长数据' : '编辑成长数据',
                style: t.titleLarge),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  setState(() => _date = AppDateUtils.day(picked));
                }
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: p.line),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_month_outlined,
                      size: 19, color: p.accent),
                  const SizedBox(width: 10),
                  Text(AppDateUtils.full(_date), style: t.bodyMedium),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _numField(_height, '身高', 'cm')),
              const SizedBox(width: 10),
              Expanded(child: _numField(_weight, '体重', 'kg')),
              const SizedBox(width: 10),
              Expanded(child: _numField(_head, '头围', 'cm')),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(hintText: '备注（可选）'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('保存')),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _delete,
                  child:
                      Text('删除', style: TextStyle(color: p.favorite)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, String unit) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(labelText: '$label ($unit)'),
    );
  }
}

/// 成长页：数据 + 里程碑。
class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key});

  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('成长')),
      floatingActionButton: _segment == 0
          ? FloatingActionButton.extended(
              onPressed: () => showGrowthEntrySheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('记一笔'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: p.card,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _segmentButton(0, '成长数据'),
                  _segmentButton(1, '里程碑'),
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _segment,
              children: const [_GrowthDataView(), MilestonesView()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentButton(int index, String label) {
    final p = context.palette;
    final selected = _segment == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _segment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? p.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? p.accent : p.subInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _GrowthDataView extends StatefulWidget {
  const _GrowthDataView();

  @override
  State<_GrowthDataView> createState() => _GrowthDataViewState();
}

class _GrowthDataViewState extends State<_GrowthDataView> {
  List<GrowthEntry> _entries = [];
  GrowthMetric _metric = GrowthMetric.height;
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
    if (baby == null) return;
    final entries = await GrowthRepository().list(baby.id);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_entries.isEmpty) {
      return EmptyView(
        icon: Icons.straighten_rounded,
        title: '记录身高、体重和头围',
        message: '定期测量，见证一点一滴的成长',
        actionLabel: '添加第一条数据',
        onAction: () => showGrowthEntrySheet(context),
      );
    }

    final withMetric = _entries
        .where((e) => e.valueOf(_metric) != null)
        .toList();
    final latest = withMetric.isEmpty ? null : withMetric.last;
    final prev = withMetric.length > 1
        ? withMetric[withMetric.length - 2]
        : null;
    final delta = (latest != null && prev != null)
        ? latest.valueOf(_metric)! - prev.valueOf(_metric)!
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      children: [
        // 指标切换
        Row(
          children: [
            for (final m in GrowthMetric.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(m.icon,
                      size: 16,
                      color: _metric == m ? p.accent : p.subInk),
                  label: Text(m.label),
                  selected: _metric == m,
                  onSelected: (_) => setState(() => _metric = m),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // 最新 + 变化
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.card,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最新${_metric.label}', style: t.labelSmall),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        text: _metric.format(latest?.valueOf(_metric)),
                        style: t.displaySmall?.copyWith(fontSize: 30),
                        children: [
                          TextSpan(
                              text: ' ${_metric.unit}',
                              style: t.labelSmall),
                        ],
                      ),
                    ),
                    if (latest != null)
                      Text(AppDateUtils.full(latest.date),
                          style: t.labelSmall),
                  ],
                ),
              ),
              if (delta != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: p.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${delta >= 0 ? '+' : ''}${_metric.format(delta)} ${_metric.unit}',
                    style: t.titleMedium
                        ?.copyWith(color: p.accent, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 趋势图
        if (withMetric.length >= 2)
          Container(
            height: 220,
            padding: const EdgeInsets.fromLTRB(12, 20, 20, 8),
            decoration: BoxDecoration(
              color: p.card,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: GrowthChart(entries: withMetric, metric: _metric),
          )
        else
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: p.card,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('再添加一条${_metric.label}数据后，这里会显示趋势图',
                style: t.bodySmall, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 20),
        Text('历史数据', style: t.titleMedium),
        const SizedBox(height: 8),
        for (var i = _entries.length - 1; i >= 0; i--)
          _entryTile(_entries[i], i > 0 ? _entries[i - 1] : null, p, t),
      ],
    );
  }

  Widget _entryTile(
      GrowthEntry e, GrowthEntry? prev, AppPalette p, TextTheme t) {
    String deltaText(double? cur, double? prevV, String unit) {
      if (cur == null || prevV == null) return '';
      final d = cur - prevV;
      if (d == 0) return '';
      return ' (${d > 0 ? '+' : ''}${d.toStringAsFixed(1)}$unit)';
    }

    final parts = <String>[
      if (e.heightCm != null)
        '身高 ${e.heightCm!.toStringAsFixed(1)}cm${deltaText(e.heightCm, prev?.heightCm, '')}',
      if (e.weightKg != null)
        '体重 ${e.weightKg!.toStringAsFixed(2)}kg${deltaText(e.weightKg, prev?.weightKg, '')}',
      if (e.headCm != null) '头围 ${e.headCm!.toStringAsFixed(1)}cm',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showGrowthEntrySheet(context, existing: e),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppDateUtils.full(e.date), style: t.titleMedium),
                const SizedBox(height: 4),
                Text(parts.join(' · '),
                    style: t.bodySmall?.copyWith(color: p.ink)),
                if (e.note.isNotEmpty)
                  Text(e.note, style: t.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 简洁高级的趋势图。
class GrowthChart extends StatelessWidget {
  final List<GrowthEntry> entries;
  final GrowthMetric metric;

  const GrowthChart({super.key, required this.entries, required this.metric});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < entries.length; i++) {
      spots.add(FlSpot(i.toDouble(), entries[i].valueOf(metric)!));
    }
    final values = spots.map((s) => s.y);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxV - minV) * 0.25).clamp(0.5, 5.0);

    String labelFor(int i) {
      final d = entries[i].date;
      return entries.length > 6 && (maxV - minV) >= 0
          ? '${d.year % 100}/${d.month}'
          : '${d.month}/${d.day}';
    }

    final labelIndexes = <int>{0, entries.length - 1};
    if (entries.length > 2) labelIndexes.add(entries.length ~/ 2);
    if (entries.length > 4) labelIndexes.add(entries.length ~/ 4 * 3);

    return LineChart(
      LineChartData(
        minY: minV - pad,
        maxY: maxV + pad,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: p.line, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, meta) => Text(
                v.toStringAsFixed(1),
                style: t.labelSmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (v != i.toDouble() || !labelIndexes.contains(i)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labelFor(i),
                      style: t.labelSmall?.copyWith(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => p.ink,
            getTooltipItems: (touched) => [
              for (final s in touched)
                LineTooltipItem(
                  '${metric.format(s.y)} ${metric.unit}\n${AppDateUtils.compact(entries[s.x.toInt()].date)}',
                  TextStyle(color: p.scaffold, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: p.accent,
            barWidth: 2.4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                radius: index == spots.length - 1 ? 4.5 : 3,
                color: p.accent,
                strokeWidth: 1.5,
                strokeColor: p.card,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: p.accent.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 350),
    );
  }
}
