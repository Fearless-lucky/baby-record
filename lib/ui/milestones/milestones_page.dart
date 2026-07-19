import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';
import '../record/edit_record_page.dart';
import '../record/record_detail_page.dart';
import '../timeline/record_card.dart';

/// 添加 / 编辑里程碑的底部表单。保存成功时返回该里程碑。
Future<Milestone?> showMilestoneSheet(BuildContext context,
    {Milestone? existing}) async {
  return showModalBottomSheet<Milestone>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MilestoneSheet(existing: existing),
  );
}

class _MilestoneSheet extends StatefulWidget {
  final Milestone? existing;
  const _MilestoneSheet({this.existing});

  @override
  State<_MilestoneSheet> createState() => _MilestoneSheetState();
}

class _MilestoneSheetState extends State<_MilestoneSheet> {
  late DateTime _date;
  late final TextEditingController _title;
  late final TextEditingController _note;
  String _iconKey = 'custom';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = AppDateUtils.day(e?.date ?? DateTime.now());
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _iconKey = e?.iconKey ?? 'custom';
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写里程碑名称')));
      return;
    }
    final repo = MilestoneRepository();
    final milestone = widget.existing == null
        ? Milestone(
            id: newId(),
            babyId: baby.id,
            title: _title.text.trim(),
            iconKey: _iconKey,
            date: _date,
            note: _note.text.trim(),
            createdAt: DateTime.now(),
            author: context.read<AppState>().authorName,
          )
        : Milestone(
            id: widget.existing!.id,
            babyId: baby.id,
            title: _title.text.trim(),
            iconKey: _iconKey,
            date: _date,
            note: _note.text.trim(),
            createdAt: widget.existing!.createdAt,
            author: widget.existing!.author,
          );
    if (widget.existing == null) {
      await repo.insert(milestone);
    } else {
      await repo.update(milestone);
    }
    if (!mounted) return;
    context.read<AppState>().bumpData();
    Navigator.pop(context, milestone);
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
            Text(widget.existing == null ? '添加里程碑' : '编辑里程碑',
                style: t.titleLarge),
            const SizedBox(height: 16),
            Text('常用', style: t.labelSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in kMilestonePresets)
                  ChoiceChip(
                    avatar: Icon(kMilestoneIcons[preset.$2],
                        size: 15,
                        color: _title.text == preset.$1
                            ? p.accent
                            : p.subInk),
                    label: Text(preset.$1),
                    selected: _title.text == preset.$1,
                    onSelected: (_) => setState(() {
                      _title.text = preset.$1;
                      _iconKey = preset.$2;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              maxLength: 20,
              decoration: const InputDecoration(
                  labelText: '名称', hintText: '也可以自定义，例如：第一次坐飞机'),
              onChanged: (_) => setState(() => _iconKey = 'custom'),
            ),
            const SizedBox(height: 10),
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
            TextField(
              controller: _note,
              maxLines: 2,
              decoration:
                  const InputDecoration(hintText: '想记住的细节（可选）'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 里程碑列表（嵌入成长页）。
class MilestonesView extends StatefulWidget {
  const MilestonesView({super.key});

  @override
  State<MilestonesView> createState() => _MilestonesViewState();
}

class _MilestonesViewState extends State<MilestonesView> {
  List<Milestone> _items = [];
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
    final items = await MilestoneRepository().list(baby.id);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baby = context.watch<AppState>().currentBaby;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.emoji_events_outlined,
        title: '记录每一个"第一次"',
        message: '第一次翻身、第一次走路、第一次叫妈妈……',
        actionLabel: '添加里程碑',
        onAction: () => showMilestoneSheet(context),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => showMilestoneSheet(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加'),
          ),
        ),
        for (var i = 0; i < _items.length; i++)
          _MilestoneTile(
            milestone: _items[i],
            baby: baby,
            isLast: i == _items.length - 1,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      MilestoneDetailPage(milestoneId: _items[i].id)),
            ),
          ),
      ],
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  final Milestone milestone;
  final Baby? baby;
  final bool isLast;
  final VoidCallback onTap;

  const _MilestoneTile({
    required this.milestone,
    required this.baby,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(milestone.icon, color: p.accent, size: 21),
              ),
              if (!isLast)
                Container(width: 1.5, height: 46, color: p.line),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(milestone.title, style: t.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    baby == null
                        ? AppDateUtils.full(milestone.date)
                        : '${AppDateUtils.full(milestone.date)} · ${baby!.ageText(milestone.date)}',
                    style: t.bodySmall,
                  ),
                  if (milestone.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(milestone.note,
                        style: t.bodySmall?.copyWith(color: p.ink),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(Icons.chevron_right_rounded, color: p.subInk),
          ),
        ],
      ),
    );
  }
}

/// 里程碑详情：说明 + 关联的照片与故事。
class MilestoneDetailPage extends StatefulWidget {
  final String milestoneId;
  const MilestoneDetailPage({super.key, required this.milestoneId});

  @override
  State<MilestoneDetailPage> createState() => _MilestoneDetailPageState();
}

class _MilestoneDetailPageState extends State<MilestoneDetailPage> {
  Milestone? _milestone;
  List<Moment> _moments = [];
  bool _notFound = false;
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
    final baby = context.read<AppState>().currentBaby;
    final m = await MilestoneRepository().byId(widget.milestoneId);
    List<Moment> moments = [];
    if (m != null && baby != null) {
      moments = await MomentRepository().query(baby.id,
          filter: MomentFilter(milestoneId: m.id), limit: 100);
    }
    if (!mounted) return;
    setState(() {
      _milestone = m;
      _moments = moments;
      _notFound = m == null;
    });
  }

  Future<void> _delete() async {
    final ok = await confirmDanger(
      context,
      title: '删除这个里程碑？',
      message: '关联的记录会保留，但不再关联此里程碑。',
    );
    if (!ok) return;
    await MilestoneRepository().delete(widget.milestoneId);
    if (!mounted) return;
    context.read<AppState>().bumpData();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final baby = context.watch<AppState>().currentBaby;
    final m = _milestone;

    if (_notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(
            icon: Icons.search_off_rounded, title: '里程碑不存在'),
      );
    }
    if (m == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('里程碑'),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showMilestoneSheet(context, existing: m),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _delete,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  EditRecordPage(presetMilestoneId: m.id)),
        ),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('添加故事'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                      color: p.accentSoft, shape: BoxShape.circle),
                  child: Icon(m.icon, color: p.accent, size: 34),
                ),
                const SizedBox(height: 16),
                Text(m.title, style: t.displaySmall),
                const SizedBox(height: 6),
                Text(
                  baby == null
                      ? AppDateUtils.full(m.date)
                      : '${AppDateUtils.full(m.date)} · ${baby.ageText(m.date)} · 第${baby.dayOfLife(m.date)}天',
                  style: t.bodySmall,
                ),
                if (m.note.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(m.note,
                      style: t.bodyLarge, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
          const SectionHeader('照片与故事'),
          if (_moments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('还没有为这个里程碑添加记录，点击右下角按钮添加。',
                  style: t.bodySmall, textAlign: TextAlign.center),
            )
          else
            for (final moment in _moments)
              RecordCard(
                moment: moment,
                baby: baby,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          RecordDetailPage(momentId: moment.id)),
                ),
              ),
        ],
      ),
    );
  }
}
