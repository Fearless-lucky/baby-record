import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../calendar/calendar_page.dart';
import '../common/widgets.dart';
import '../record/edit_record_page.dart';
import '../record/record_detail_page.dart';
import '../search/search_page.dart';
import 'record_card.dart';

/// 藤蔓画手：一段连续的茎，节点处生长叶子（时间即叶子）。
class VinePainter extends CustomPainter {
  final bool isMonthNode;
  final Color stemColor;
  final Color leafColor;

  VinePainter({
    required this.isMonthNode,
    required this.stemColor,
    required this.leafColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final stemPaint = Paint()
      ..color = stemColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 轻微蜿蜒的茎
    final path = Path()..moveTo(x, -2);
    final segments = (size.height / 40).ceil().clamp(1, 20);
    var y = -2.0;
    for (var i = 0; i < segments; i++) {
      final nextY = y + size.height / segments;
      final bend = (i.isEven ? 1 : -1) * 3.0;
      path.cubicTo(x + bend, y + (nextY - y) * 0.3, x - bend,
          y + (nextY - y) * 0.7, x, nextY);
      y = nextY;
    }
    canvas.drawPath(path, stemPaint);

    // 叶子：两片相对的弧线叶瓣
    final nodeY = isMonthNode ? 24.0 : 30.0;
    final leafLen = isMonthNode ? 15.0 : 10.0;
    final leafPaint = Paint()..color = leafColor;
    for (final dir in [-1, 1]) {
      final leaf = Path()
        ..moveTo(x, nodeY)
        ..quadraticBezierTo(x + dir * leafLen, nodeY - leafLen * 0.9,
            x + dir * leafLen * 1.7, nodeY - leafLen * 0.4)
        ..quadraticBezierTo(x + dir * leafLen * 0.8,
            nodeY + leafLen * 0.5, x, nodeY + 2);
      canvas.drawPath(leaf, leafPaint);
    }
    if (isMonthNode) {
      canvas.drawCircle(
          Offset(x, nodeY), 3.2, Paint()..color = stemColor);
    }
  }

  @override
  bool shouldRepaint(VinePainter old) =>
      old.isMonthNode != isMonthNode ||
      old.stemColor != stemColor ||
      old.leafColor != leafColor;
}

/// 成长时间轴：藤蔓 + 月份叶子节点，分页懒加载。
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final _repo = MomentRepository();
  final _scroll = ScrollController();
  final List<Moment> _moments = [];
  List<Tag> _tags = [];
  String? _tagId;
  bool _favoriteOnly = false;
  bool _loading = false;
  bool _hasMore = true;
  bool _initialLoaded = false;
  Object? _error;
  int _loadedVersion = -1;
  String? _loadedBabyId;

  /// 请求序号：切换宝宝/筛选时，丢弃过期请求的结果。
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (state.version != _loadedVersion ||
        state.currentBaby?.id != _loadedBabyId) {
      _loadedVersion = state.version;
      _loadedBabyId = state.currentBaby?.id;
      _reload();
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >
            _scroll.position.maxScrollExtent - 400 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  MomentFilter get _filter => MomentFilter(
        favoriteOnly: _favoriteOnly,
        tagId: _tagId,
      );

  Future<void> _reload() async {
    final seq = ++_requestSeq;
    setState(() {
      _moments.clear();
      _hasMore = true;
      _initialLoaded = false;
      _error = null;
    });
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) {
      setState(() => _initialLoaded = true);
      return;
    }
    final tags = await TagRepository().forBaby(baby.id);
    if (!mounted || seq != _requestSeq) return;
    _tags = tags;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null || _loading) return;
    final seq = _requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.query(baby.id,
          filter: _filter, offset: _moments.length);
      // 过期请求直接丢弃
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _moments.addAll(page);
        _hasMore = page.length >= MomentRepository.pageSize;
        _loading = false;
        _initialLoaded = true;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = e;
        _loading = false;
        _initialLoaded = true;
      });
    }
  }

  Color _stemColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFF9BAE8C)
          : const Color(0xFF66755B);

  Color _leafColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFB9CBA8)
          : const Color(0xFF4E5C46);

  Widget _vineItem({required bool isMonthNode, required Widget child}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: CustomPaint(
              painter: VinePainter(
                isMonthNode: isMonthNode,
                stemColor: _stemColor(context),
                leafColor: _leafColor(context),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  List<Widget> _buildGrouped(TextTheme t, Baby? baby) {
    final widgets = <Widget>[];
    String? lastKey;
    for (final m in _moments) {
      final key = '${m.date.year}-${m.date.month}';
      if (key != lastKey) {
        lastKey = key;
        widgets.add(_vineItem(
          isMonthNode: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 22, 24, 8),
            child: Text(
              AppDateUtils.yearMonth(m.date),
              style: t.displaySmall?.copyWith(fontSize: 24),
            ),
          ),
        ));
      }
      final heroTag = 'tl_${m.id}';
      widgets.add(_vineItem(
        isMonthNode: false,
        child: RecordCard(
          moment: m,
          baby: baby,
          heroTag: heroTag,
          horizontalPadding: 0,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => RecordDetailPage(
                    momentId: m.id, heroTag: heroTag)),
          ),
        ),
      ));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final baby = context.watch<AppState>().currentBaby;
    final filtering = _favoriteOnly || _tagId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('时间轴'),
        actions: [
          IconButton(
            tooltip: '只看收藏',
            icon: Icon(
              _favoriteOnly
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: _favoriteOnly ? p.favorite : p.ink,
            ),
            onPressed: () {
              setState(() => _favoriteOnly = !_favoriteOnly);
              _reload();
            },
          ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
          IconButton(
            tooltip: '日历',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CalendarPage())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EditRecordPage())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('记录'),
      ),
      body: Column(
        children: [
          if (_tags.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      selected: _tagId == null,
                      onSelected: (_) {
                        setState(() => _tagId = null);
                        _reload();
                      },
                    ),
                  ),
                  for (final tag in _tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('# ${tag.name}'),
                        selected: _tagId == tag.id,
                        onSelected: (v) {
                          setState(() => _tagId = v ? tag.id : null);
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _buildBody(p, t, baby, filtering)),
        ],
      ),
    );
  }

  Widget _buildBody(
      AppPalette p, TextTheme t, Baby? baby, bool filtering) {
    if (_error != null) {
      return ErrorView(message: '$_error', onRetry: _reload);
    }
    if (!_initialLoaded) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_moments.isEmpty) {
      if (filtering) {
        return const EmptyView(
          icon: Icons.filter_alt_off_outlined,
          title: '没有符合条件的记录',
          message: '试试调整筛选条件',
        );
      }
      return EmptyView(
        icon: Icons.auto_stories_outlined,
        title: '开始记录成长吧',
        message: '每一个平凡的今天，都是未来最珍贵的回忆',
        actionLabel: '写下第一条',
        onAction: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EditRecordPage())),
      );
    }
    return RefreshIndicator(
      color: p.accent,
      onRefresh: _reload,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(right: 20, bottom: 100),
        cacheExtent: 800,
        children: [
          ..._buildGrouped(t, baby),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (!_hasMore && _moments.length > 10)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text('— 藤蔓的尽头是全部回忆 —',
                  style: t.labelSmall, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}
