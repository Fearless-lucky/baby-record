import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';
import '../record/record_detail_page.dart';
import '../timeline/record_card.dart';

/// 日历与回忆：按月查看，支持"往年今日"。
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selected;
  Set<int> _daysWithRecords = {};
  Map<int, String> _covers = {};
  Set<int> _milestoneDays = {};
  Set<int> _memoryDays = {};
  List<Moment> _dayMoments = [];
  List<Moment> _memories = [];
  int _filter = 0; // 0 全部 / 1 照片 / 2 文字 / 3 里程碑
  int _loadedVersion = -1;
  String? _loadedBabyId;

  @override
  void initState() {
    super.initState();
    _month = AppDateUtils.monthStart(DateTime.now());
    _selected = AppDateUtils.day(DateTime.now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (state.version != _loadedVersion ||
        state.currentBaby?.id != _loadedBabyId) {
      _loadedVersion = state.version;
      _loadedBabyId = state.currentBaby?.id;
      _loadMonth();
    }
  }

  Future<void> _loadMonth() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    final repo = MomentRepository();
    final (days, covers, milestoneDays, memoryDays) = await (
      repo.daysWithMoments(baby.id, _month.year, _month.month),
      repo.monthCovers(baby.id, _month.year, _month.month),
      MilestoneRepository().daysInMonth(baby.id, _month.year, _month.month),
      repo.monthMemoryDays(baby.id, _month.year, _month.month),
    ).wait;
    if (!mounted) return;
    setState(() {
      _daysWithRecords = days;
      _covers = covers;
      _milestoneDays = milestoneDays;
      _memoryDays = memoryDays;
    });
    _loadDay();
  }

  Future<void> _loadDay() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    final repo = MomentRepository();
    final moments = await repo.query(baby.id,
        filter: MomentFilter(from: _selected, to: _selected), limit: 50);
    final memories = await repo.onThisDay(baby.id, _selected);
    if (!mounted) return;
    setState(() {
      _dayMoments = moments;
      _memories = memories;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1, 12);
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final baby = context.watch<AppState>().currentBaby;

    return Scaffold(
      appBar: AppBar(title: const Text('日历与回忆')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          // 月份导航
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _changeMonth(-1),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppDateUtils.yearMonth(_month),
                        style: t.headlineMedium,
                      ),
                      if (baby != null &&
                          baby.birthDate.month == _month.month) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7BE4B)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cake_rounded,
                                  size: 13, color: Color(0xFFE0A428)),
                              SizedBox(width: 3),
                              Text('生日月',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFE0A428),
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          // 星期表头
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Text(w,
                        textAlign: TextAlign.center,
                        style: t.labelSmall),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _buildGrid(p, t),
          const SizedBox(height: 6),
          // 图例
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _legend(p.accent, '记录'),
                const SizedBox(width: 14),
                _legend(const Color(0xFFF7BE4B), '里程碑'),
                const SizedBox(width: 14),
                _legend(const Color(0xFF7C6AE6), '往年今日'),
              ],
            ),
          ),
          const Divider(height: 28),
          // 选中日期 + 内容筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '${AppDateUtils.full(_selected)} ${AppDateUtils.weekday(_selected)}',
              style: t.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (i, label) in const [
                  (0, '全部'),
                  (1, '照片'),
                  (2, '文字'),
                  (3, '里程碑'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == i,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _filter = i),
                  ),
              ],
            ),
          ),
          if (_filteredDayMoments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                  _dayMoments.isEmpty ? '这一天还没有记录' : '没有符合筛选的内容',
                  style: t.bodySmall, textAlign: TextAlign.center),
            )
          else
            for (final m in _filteredDayMoments)
              RecordCard(
                moment: m,
                baby: baby,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => RecordDetailPage(momentId: m.id)),
                ),
              ),
          if (_memories.isNotEmpty) ...[
            const SectionHeader('往年今日'),
            for (final m in _memories)
              RecordCard(
                moment: m,
                baby: baby,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => RecordDetailPage(momentId: m.id)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  List<Moment> get _filteredDayMoments {
    switch (_filter) {
      case 1:
        return _dayMoments.where((m) => m.media.isNotEmpty).toList();
      case 2:
        return _dayMoments
            .where((m) => m.content.trim().isNotEmpty)
            .toList();
      case 3:
        return _dayMoments.where((m) => m.milestoneId != null).toList();
      default:
        return _dayMoments;
    }
  }

  Widget _buildGrid(AppPalette p, TextTheme t) {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;
    final leading = firstDay.weekday - 1; // 周一开头
    final total = leading + daysInMonth;
    final rows = (total / 7).ceil();
    final today = AppDateUtils.day(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _dayCell(r * 7 + c, leading, daysInMonth, today, p, t)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(int index, int leading, int daysInMonth, DateTime today,
      AppPalette p, TextTheme t) {
    final day = index - leading + 1;
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 56);
    final date = DateTime(_month.year, _month.month, day, 12);
    final isSelected = date == _selected;
    final isToday = date == today;
    final hasRecord = _daysWithRecords.contains(day);
    final hasMilestone = _milestoneDays.contains(day);
    final hasMemory = _memoryDays.contains(day);
    final cover = _covers[day];
    final isFuture = date.isAfter(today);

    Widget dot(Color color) => Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        );

    return GestureDetector(
      onTap: () {
        setState(() => _selected = date);
        _loadDay();
      },
      child: SizedBox(
        height: 56,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: p.accent, width: 2)
                      : isToday
                          ? Border.all(color: p.accent, width: 1.2)
                          : null,
                  color: cover == null && isSelected
                      ? p.accent
                      : cover == null && isToday
                          ? p.accentSoft
                          : Colors.transparent,
                ),
                child: ClipOval(
                  child: cover != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            ThumbImage(cover, cacheWidth: 120),
                            Container(
                              color: Colors.black.withValues(
                                  alpha: isSelected ? 0.15 : 0.3),
                            ),
                            Center(
                              child: Text(
                                '$day',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isSelected
                                  ? Colors.white
                                  : isFuture
                                      ? p.subInk.withValues(alpha: 0.4)
                                      : p.ink,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasRecord) dot(isSelected ? p.accent : p.accent),
                  if (hasMilestone) dot(const Color(0xFFF7BE4B)),
                  if (hasMemory) dot(const Color(0xFF7C6AE6)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
