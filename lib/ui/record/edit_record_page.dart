import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/media_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';
import '../milestones/milestones_page.dart';

class _MediaDraft {
  final MediaItem? existing;
  final XFile? picked;
  const _MediaDraft.existing(this.existing) : picked = null;
  const _MediaDraft.picked(this.picked) : existing = null;

  bool get isVideo =>
      existing?.type == MediaType.video ||
      (picked != null && MediaService.isVideoName(picked!.name));
}

/// 添加 / 编辑成长记录。
class EditRecordPage extends StatefulWidget {
  final Moment? existing;
  final String? presetMilestoneId;

  const EditRecordPage({super.key, this.existing, this.presetMilestoneId});

  @override
  State<EditRecordPage> createState() => _EditRecordPageState();
}

class _EditRecordPageState extends State<EditRecordPage> {
  late DateTime _date;
  late final TextEditingController _content;
  final List<_MediaDraft> _media = [];
  final Set<String> _removedMediaIds = {};
  List<String> _allTagNames = [];
  final Set<String> _selectedTags = {};
  List<Milestone> _milestones = [];
  String? _milestoneId;
  bool _favorite = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = AppDateUtils.day(e?.date ?? DateTime.now());
    _content = TextEditingController(text: e?.content ?? '');
    _favorite = e?.isFavorite ?? false;
    _milestoneId = widget.presetMilestoneId ?? e?.milestoneId;
    if (e != null) {
      _media.addAll(e.media.map(_MediaDraft.existing));
      _selectedTags.addAll(e.tags.map((t) => t.name));
    }
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    final tags = await TagRepository().forBaby(baby.id);
    final milestones = await MilestoneRepository().list(baby.id);
    if (!mounted) return;
    setState(() {
      _allTagNames = tags.map((t) => t.name).toList();
      _milestones = milestones;
    });
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final p = context.palette;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: p.accent),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = AppDateUtils.day(picked));
  }

  Future<void> _pickMedia() async {
    try {
      final files = await ImagePicker().pickMultipleMedia();
      if (files.isEmpty || !mounted) return;
      setState(() {
        _media.addAll(files.map(_MediaDraft.picked));
      });
      // 大视频提醒：备份与分享会明显变慢。
      for (final x in files) {
        if (MediaService.isVideoName(x.name)) {
          final size = await x.length();
          if (size > 300 * 1024 * 1024 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    '视频较大（${(size / 1024 / 1024).toStringAsFixed(0)}MB），备份和分享会更耗时')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开相册：$e')));
      }
    }
  }

  void _removeMedia(int index) {
    final d = _media[index];
    if (d.existing != null) _removedMediaIds.add(d.existing!.id);
    setState(() => _media.removeAt(index));
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '例如：第一次、户外、奶奶家'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      setState(() {
        _selectedTags.add(name);
        if (!_allTagNames.contains(name)) _allTagNames.add(name);
      });
    }
  }

  Future<void> _pickMilestone() async {
    final p = context.palette;
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: Icon(Icons.add_circle_outline_rounded,
                  color: p.accent),
              title: Text('新建里程碑',
                  style: TextStyle(
                      color: p.accent, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, '__new__'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.close_rounded, color: p.subInk),
              title: const Text('不关联里程碑'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final m in _milestones)
              ListTile(
                leading: Icon(m.icon, color: p.accent),
                title: Text(m.title),
                subtitle: Text(AppDateUtils.full(m.date)),
                trailing: _milestoneId == m.id
                    ? Icon(Icons.check_rounded, color: p.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, m.id),
              ),
          ],
        ),
      ),
    );
    if (result == '__new__' && mounted) {
      final created = await showMilestoneSheet(context);
      if (created != null && mounted) {
        final baby = context.read<AppState>().currentBaby;
        if (baby != null) {
          _milestones = await MilestoneRepository().list(baby.id);
        }
        setState(() => _milestoneId = created.id);
      }
      return;
    }
    if (result != null && mounted) {
      setState(() => _milestoneId = result.isEmpty ? null : result);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final appState = context.read<AppState>();
    final baby = appState.currentBaby;
    if (baby == null) return;
    if (_content.text.trim().isEmpty && _media.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('写点什么，或添加一张照片吧')));
      return;
    }
    setState(() => _saving = true);
    final saveSpace = appState.importSaveSpace;

    final saved = await runWithProgress<Moment>(context, task: (report) async {
      final recordId = widget.existing?.id ?? newId();
      final mediaRepo = MediaService.instance;
      final newItems = <MediaItem>[];

      try {
        // 先导入新媒体（失败时尚未改动任何旧数据）
        final kept = _media
            .where((d) => d.existing != null)
            .map((d) => d.existing!)
            .toList();
        final picked = _media.where((d) => d.picked != null).toList();
        for (var i = 0; i < picked.length; i++) {
          report('正在处理媒体 ${i + 1}/${picked.length}…');
          final x = picked[i].picked!;
          final isVideo = MediaService.isVideoName(x.name);
          newItems.add(await mediaRepo.importMedia(
            sourcePath: x.path,
            type: isVideo ? MediaType.video : MediaType.image,
            recordId: recordId,
            sortOrder: kept.length + i,
            saveSpace: saveSpace,
          ));
        }

        // 标签：确保存在并取 id
        report('正在保存…');
        final tagRepo = TagRepository();
        final tagIds = <String>[];
        for (final name in _selectedTags) {
          tagIds.add((await tagRepo.ensure(baby.id, name)).id);
        }

        final now = DateTime.now();
        final e = widget.existing;
        final moment = Moment(
          id: recordId,
          babyId: e?.babyId ?? baby.id,
          date: _date,
          content: _content.text.trim(),
          isFavorite: _favorite,
          milestoneId: _milestoneId,
          createdAt: e?.createdAt ?? now,
          updatedAt: now,
          author: e?.author ?? appState.authorName,
        );
        final allMedia = [
          for (var i = 0; i < kept.length; i++)
            MediaItem(
              id: kept[i].id,
              recordId: recordId,
              type: kept[i].type,
              file: kept[i].file,
              thumbFile: kept[i].thumbFile,
              width: kept[i].width,
              height: kept[i].height,
              sortOrder: i,
            ),
          ...newItems,
        ];
        final repo = MomentRepository();
        if (e == null) {
          await repo.insert(moment, allMedia, tagIds, null);
        } else {
          await repo.update(moment, allMedia, tagIds);
        }

        // 数据库写入成功后，才物理删除被移除的旧媒体
        final removed = widget.existing?.media
                .where((m) => _removedMediaIds.contains(m.id))
                .toList() ??
            [];
        await mediaRepo.deleteMediaFiles(removed
            .expand((m) => [m.file, if (m.thumbFile != null) m.thumbFile!]));
        return moment;
      } catch (_) {
        // 失败时清理本次新导入的文件，避免留下孤儿文件
        await mediaRepo.deleteMediaFiles(newItems
            .expand((m) => [m.file, if (m.thumbFile != null) m.thumbFile!]));
        rethrow;
      }
    });

    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) {
      appState.bumpData();
      Navigator.pop(context, saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final baby = context.read<AppState>().currentBaby;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑记录' : '记录此刻'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FavoriteButton(
              active: _favorite,
              onTap: () => setState(() => _favorite = !_favorite),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          // 日期
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: p.card,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_outlined,
                      size: 20, color: p.accent),
                  const SizedBox(width: 12),
                  Text(AppDateUtils.full(_date), style: t.titleMedium),
                  const SizedBox(width: 8),
                  Text(
                    baby == null
                        ? AppDateUtils.weekday(_date)
                        : '${AppDateUtils.weekday(_date)} · ${baby.ageText(_date)}',
                    style: t.bodySmall,
                  ),
                  const Spacer(),
                  Icon(Icons.keyboard_arrow_down_rounded, color: p.subInk),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 正文
          TextField(
            controller: _content,
            maxLines: null,
            minLines: 4,
            style: t.bodyLarge,
            decoration: const InputDecoration(
              hintText: '今天发生了什么值得记住的事？',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          // 媒体
          _buildMediaGrid(p, t),
          const SizedBox(height: 24),
          // 标签
          Row(
            children: [
              Text('标签', style: t.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addTag,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新标签'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in _allTagNames)
                ChoiceChip(
                  label: Text(name),
                  selected: _selectedTags.contains(name),
                  onSelected: (v) => setState(() {
                    v ? _selectedTags.add(name) : _selectedTags.remove(name);
                  }),
                ),
              if (_allTagNames.isEmpty)
                Text('还没有标签，点击右上角"新标签"创建',
                    style: t.bodySmall),
            ],
          ),
          const SizedBox(height: 24),
          // 里程碑
          Text('里程碑', style: t.titleMedium),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickMilestone,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: p.card,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.emoji_events_outlined,
                      size: 20, color: p.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _milestoneId == null
                          ? '不关联里程碑'
                          : _milestones
                                  .where((m) => m.id == _milestoneId)
                                  .map((m) => m.title)
                                  .firstOrNull ??
                              '已关联里程碑',
                      style: t.bodyMedium,
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: p.subInk),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_isEdit ? '保存修改' : '保存记录'),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaGrid(AppPalette p, TextTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('照片与视频', style: t.titleMedium),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _media.length + 1,
          itemBuilder: (context, i) {
            if (i == _media.length) {
              return InkWell(
                onTap: _pickMedia,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.card,
                    border: Border.all(color: p.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          color: p.accent, size: 26),
                      const SizedBox(height: 6),
                      Text('添加', style: t.labelSmall),
                    ],
                  ),
                ),
              );
            }
            final d = _media[i];
            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (d.existing != null)
                    ThumbImage(d.existing!.thumbFile ?? d.existing!.file,
                        cacheWidth: 400)
                  else
                    Image.file(
                      File(d.picked!.path),
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (_, __, ___) =>
                          Container(color: p.accentSoft),
                    ),
                  if (d.isVideo)
                    const Center(child: VideoBadge()),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeMedia(i),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
