import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';
import '../record/record_detail_page.dart';

/// 搜索与筛选。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<Moment> _results = [];
  List<Tag> _tags = [];
  List<Milestone> _milestones = [];
  MomentFilter _filter = const MomentFilter();
  bool _searched = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  Future<void> _loadMeta() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    final tags = await TagRepository().forBaby(baby.id);
    final milestones = await MilestoneRepository().list(baby.id);
    if (mounted) {
      setState(() {
        _tags = tags;
        _milestones = milestones;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    setState(() => _loading = true);
    final results = await MomentRepository().query(
      baby.id,
      filter: _filter.copyWith(
          keyword: () =>
              _controller.text.trim().isEmpty ? null : _controller.text.trim()),
      limit: 200,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _searched = true;
      _loading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final p = context.palette;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _filter.from != null && _filter.to != null
          ? DateTimeRange(start: _filter.from!, end: _filter.to!)
          : null,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: p.accent),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _filter = _filter.copyWith(
            from: () => range.start, to: () => range.end);
      });
      _search();
    }
  }

  /// 通用单选弹窗。用哨兵值区分"选择了'全部'"与"下滑关闭"。
  Future<void> _pickFromList({
    required String title,
    required List<(String, String?)> options,
    required String? current,
    required void Function(String?) onSelect,
  }) async {
    const none = '__none__';
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(title,
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final (label, value) in options)
              ListTile(
                title: Text(label),
                trailing: (value ?? none) == (current ?? none)
                    ? Icon(Icons.check_rounded,
                        color: context.palette.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, value ?? none),
              ),
          ],
        ),
      ),
    );
    // 下滑关闭时 selected 为 null，不做修改。
    if (selected != null) {
      onSelect(selected == none ? null : selected);
      _search();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: '搜索记录内容…',
            border: InputBorder.none,
            filled: false,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _controller.clear();
                      _search();
                    },
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: _search,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _filterChip(
                  label: '收藏',
                  icon: _filter.favoriteOnly
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  selected: _filter.favoriteOnly,
                  onTap: () {
                    setState(() => _filter = _filter.copyWith(
                        favoriteOnly: !_filter.favoriteOnly));
                    _search();
                  },
                ),
                _filterChip(
                  label: '有照片/视频',
                  icon: Icons.photo_library_outlined,
                  selected: _filter.withMediaOnly,
                  onTap: () {
                    setState(() => _filter = _filter.copyWith(
                        withMediaOnly: !_filter.withMediaOnly));
                    _search();
                  },
                ),
                _filterChip(
                  label: _filter.from == null
                      ? '日期范围'
                      : '${AppDateUtils.monthDay(_filter.from!)} – ${AppDateUtils.monthDay(_filter.to!)}',
                  icon: Icons.date_range_rounded,
                  selected: _filter.from != null,
                  onTap: _pickDateRange,
                  onClear: _filter.from == null
                      ? null
                      : () {
                          setState(() => _filter = _filter.copyWith(
                              from: () => null, to: () => null));
                          _search();
                        },
                ),
                _filterChip(
                  label: _filter.tagId == null
                      ? '标签'
                      : '# ${_tags.where((e) => e.id == _filter.tagId).map((e) => e.name).firstOrNull ?? ''}',
                  icon: Icons.label_outline_rounded,
                  selected: _filter.tagId != null,
                  onTap: () => _pickFromList(
                    title: '按标签筛选',
                    options: [
                      ('全部标签', null),
                      ..._tags.map((e) => (e.name, e.id)),
                    ],
                    current: _filter.tagId,
                    onSelect: (v) =>
                        setState(() => _filter = _filter.copyWith(tagId: () => v)),
                  ),
                ),
                _filterChip(
                  label: _filter.milestoneId == null
                      ? '里程碑'
                      : _milestones
                              .where((e) => e.id == _filter.milestoneId)
                              .map((e) => e.title)
                              .firstOrNull ??
                          '里程碑',
                  icon: Icons.emoji_events_outlined,
                  selected: _filter.milestoneId != null,
                  onTap: () => _pickFromList(
                    title: '按里程碑筛选',
                    options: [
                      ('全部里程碑', null),
                      ..._milestones.map((e) => (e.title, e.id)),
                    ],
                    current: _filter.milestoneId,
                    onSelect: (v) => setState(
                        () => _filter = _filter.copyWith(milestoneId: () => v)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: _buildBody(p, t)),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? p.accentSoft : p.card,
            border: Border.all(color: selected ? p.accent : p.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15, color: selected ? p.accent : p.subInk),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: selected ? p.accent : p.ink,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
              if (onClear != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close_rounded,
                      size: 14, color: p.accent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppPalette p, TextTheme t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (!_searched) {
      return const EmptyView(
        icon: Icons.manage_search_rounded,
        title: '搜索成长记忆',
        message: '输入关键词，或使用上方筛选条件',
      );
    }
    if (_results.isEmpty) {
      return const EmptyView(
        icon: Icons.search_off_rounded,
        title: '没有找到相关记录',
        message: '换个关键词或筛选条件试试',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Text(
            _results.length >= 200
                ? '仅显示前 200 条，可用筛选条件缩小范围'
                : '${_results.length} 条记录',
            style: t.labelSmall,
          ),
        ),
        for (final m in _results) _resultTile(m, p, t),
      ],
    );
  }

  Widget _resultTile(Moment m, AppPalette p, TextTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => RecordDetailPage(momentId: m.id)),
          ),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: m.cover != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ThumbImage(
                                  m.cover!.thumbFile ?? m.cover!.file,
                                  cacheWidth: 240),
                              if (m.cover!.type == MediaType.video)
                                const Center(child: VideoBadge(size: 24)),
                            ],
                          )
                        : Container(
                            color: p.accentSoft,
                            child: Icon(Icons.notes_rounded,
                                color: p.accent),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(AppDateUtils.full(m.date),
                              style: t.titleMedium
                                  ?.copyWith(fontSize: 14)),
                          if (m.isFavorite) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.favorite_rounded,
                                size: 13, color: p.favorite),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
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
                Icon(Icons.chevron_right_rounded, color: p.subInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
