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
  List<Moment> _dayMoments = [];
  List<Moment> _memories = [];
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
    final days = await MomentRepository()
        .daysWithMoments(baby.id, _month.year, _month.month);
    if (!mounted) return;
    setState(() => _daysWithRecords = days);
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
                  child: Text(
                    AppDateUtils.yearMonth(_month),
                    style: t.headlineMedium,
                    textAlign: TextAlign.center,
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
          const Divider(height: 28),
          // 选中日期
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '${AppDateUtils.full(_selected)} ${AppDateUtils.weekday(_selected)}',
              style: t.titleLarge,
            ),
          ),
          if (_dayMoments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text('这一天还没有记录',
                  style: t.bodySmall, textAlign: TextAlign.center),
            )
          else
            for (final m in _dayMoments)
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
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 52);
    final date = DateTime(_month.year, _month.month, day, 12);
    final isSelected = date == _selected;
    final isToday = date == today;
    final hasRecord = _daysWithRecords.contains(day);
    final isFuture = date.isAfter(today);

    return GestureDetector(
      onTap: () {
        setState(() => _selected = date);
        _loadDay();
      },
      child: SizedBox(
        height: 52,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? p.accent
                      : isToday
                          ? p.accentSoft
                          : Colors.transparent,
                ),
                child: Center(
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
              const SizedBox(height: 2),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasRecord
                      ? (isSelected ? Colors.white : p.accent)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
