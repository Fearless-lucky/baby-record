import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';
import '../record/record_detail_page.dart';

/// 去年今天：沉浸式的历年今日回顾（竖向翻页）。
class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key});

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  List<Moment>? _moments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    final moments =
        await MomentRepository().onThisDay(baby.id, DateTime.now());
    if (mounted) setState(() => _moments = moments);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final moments = _moments;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('往年今日', style: TextStyle(color: Colors.white)),
      ),
      extendBodyBehindAppBar: true,
      body: moments == null
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white54))
          : moments.isEmpty
              ? _empty(p)
              : PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: moments.length,
                  itemBuilder: (context, i) =>
                      _MemoryPage(moment: moments[i], index: i, total: moments.length),
                ),
    );
  }

  Widget _empty(AppPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off_rounded,
                size: 64, color: Colors.white.withValues(alpha: 0.6)),
            const SizedBox(height: 20),
            const Text('往年的今天还没有记录',
                style: TextStyle(color: Colors.white, fontSize: 17)),
            const SizedBox(height: 8),
            Text('明年的今天，这里就会出现今天的回忆',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _MemoryPage extends StatelessWidget {
  final Moment moment;
  final int index;
  final int total;

  const _MemoryPage(
      {required this.moment, required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    final baby = context.read<AppState>().currentBaby;
    final now = DateTime.now();
    final years = now.year - moment.date.year;
    final cover = moment.cover;
    final t = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RecordDetailPage(momentId: moment.id)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            ThumbImage(cover.thumbFile ?? cover.file, cacheWidth: 1080)
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3A312A), Color(0xFF1E1A16)],
                ),
              ),
              child: Center(
                child: Icon(Icons.format_quote_rounded,
                    size: 90,
                    color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
                stops: const [0.45, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 28,
            right: 28,
            bottom: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$years 年前的今天',
                    style: t.displayLarge
                        ?.copyWith(color: Colors.white, fontSize: 36)),
                const SizedBox(height: 8),
                Text(
                  baby == null
                      ? AppDateUtils.full(moment.date)
                      : '${AppDateUtils.full(moment.date)} · ${baby.ageText(moment.date)}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14),
                ),
                if (moment.content.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    moment.content,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 15.5,
                        height: 1.6),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 18),
                Text('${index + 1} / $total · 点击查看完整记录',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
