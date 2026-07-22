import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/daily_album_service.dart';
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

  /// 新建时的默认日期（如"补记昨天"）。
  final DateTime? presetDate;

  /// 新建时直接带入的媒体（如快捷拍照/选照片）。
  final List<XFile>? initialMedia;

  /// 打开后键盘直接聚焦正文（"写一句话"/拍完照引导）。
  final bool autofocusContent;

  const EditRecordPage({
    super.key,
    this.existing,
    this.presetMilestoneId,
    this.presetDate,
    this.initialMedia,
    this.autofocusContent = false,
  });

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
  final DailyAlbumService _dailyAlbumService = DailyAlbumService();
  List<DailyAlbumCandidate> _dailyPhotos = [];
  final Set<String> _selectedDailyPhotoIds = {};
  final Set<String> _addedDailyPhotoIds = {};
  bool _loadingDailyPhotos = false;
  bool _addingDailyPhotos = false;
  bool _albumPermissionDenied = false;
  String? _dailyPhotoError;
  int _dailyPhotoTotal = 0;
  int _analyzedPhotoCount = 0;
  int _dailyPhotoRequest = 0;
  bool _faceOnly = false;
  Timer? _draftTimer;

  bool get _isEdit => widget.existing != null;

  /// 只有不带任何预设打开"记录今天"时才恢复草稿。
  bool get _useDraft =>
      widget.existing == null &&
      widget.presetDate == null &&
      (widget.initialMedia?.isEmpty ?? true);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = AppDateUtils.day(e?.date ?? widget.presetDate ?? DateTime.now());
    _content = TextEditingController(text: e?.content ?? '');
    _favorite = e?.isFavorite ?? false;
    _milestoneId = widget.presetMilestoneId ?? e?.milestoneId;
    if (e != null) {
      _media.addAll(e.media.map(_MediaDraft.existing));
      _selectedTags.addAll(e.tags.map((t) => t.name));
    }
    final initial = widget.initialMedia;
    if (initial != null && initial.isNotEmpty) {
      _media.addAll(initial.map(_MediaDraft.picked));
    }
    _content.addListener(_scheduleDraftSave);
    if (_useDraft) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraft());
    }
    _loadMeta();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDailyPhotos());
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
    _dailyPhotoRequest++;
    _draftTimer?.cancel();
    _dailyAlbumService.dispose();
    _content.dispose();
    super.dispose();
  }

  // ---------------- 自动草稿 ----------------

  String? _draftKey() {
    final baby = context.read<AppState>().currentBaby;
    return baby == null ? null : 'recordDraft_${baby.id}';
  }

  void _scheduleDraftSave() {
    if (!_useDraft) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (!mounted || !_useDraft) return;
    final key = _draftKey();
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final mediaPaths = [
      for (final d in _media)
        if (d.picked != null) d.picked!.path,
    ];
    final empty = _content.text.trim().isEmpty &&
        mediaPaths.isEmpty &&
        _selectedTags.isEmpty &&
        _milestoneId == null;
    if (empty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode({
        'date': _date.millisecondsSinceEpoch,
        'content': _content.text,
        'tags': _selectedTags.toList(),
        'favorite': _favorite,
        'milestoneId': _milestoneId,
        'media': mediaPaths,
      }),
    );
  }

  Future<void> _clearDraft() async {
    final key = _draftKey();
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> _restoreDraft() async {
    final key = _draftKey();
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || !mounted) return;
    try {
      final m = jsonDecode(raw) as Map<String, Object?>;
      final paths = (m['media'] as List?)?.whereType<String>() ?? const [];
      final restoredMedia = [
        for (final p in paths)
          if (File(p).existsSync()) _MediaDraft.picked(XFile(p)),
      ];
      setState(() {
        final dateMs = m['date'] as int?;
        if (dateMs != null) {
          _date = AppDateUtils.day(
              DateTime.fromMillisecondsSinceEpoch(dateMs));
        }
        _content.text = (m['content'] as String?) ?? '';
        _selectedTags
          ..clear()
          ..addAll((m['tags'] as List?)?.whereType<String>() ?? const []);
        _favorite = (m['favorite'] as bool?) ?? false;
        _milestoneId = m['milestoneId'] as String?;
        _media.addAll(restoredMedia);
      });
      _loadDailyPhotos();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已恢复上次未保存的草稿'),
          action: SnackBarAction(
            label: '丢弃',
            onPressed: () {
              setState(() {
                _content.clear();
                _selectedTags.clear();
                _favorite = false;
                _milestoneId = null;
                _media.clear();
              });
              _clearDraft();
            },
          ),
        ),
      );
    } catch (_) {
      await prefs.remove(key);
    }
  }

  Future<void> _pickDate() async {
    final p = context.palette;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder:
          (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(
                ctx,
              ).colorScheme.copyWith(primary: p.accent),
            ),
            child: child!,
          ),
    );
    if (picked != null) {
      final day = AppDateUtils.day(picked);
      if (day == _date) return;
      setState(() => _date = day);
      _scheduleDraftSave();
      await _loadDailyPhotos();
    }
  }

  Future<void> _loadDailyPhotos() async {
    final request = ++_dailyPhotoRequest;
    setState(() {
      _loadingDailyPhotos = true;
      _albumPermissionDenied = false;
      _dailyPhotoError = null;
      _dailyPhotos = [];
      _selectedDailyPhotoIds.clear();
      _dailyPhotoTotal = 0;
      _analyzedPhotoCount = 0;
    });

    try {
      final limit = context.read<AppState>().dailyPhotoLimit;
      final batch = await _dailyAlbumService.loadForDay(_date, limit: limit);
      if (!mounted || request != _dailyPhotoRequest) return;
      setState(() {
        _dailyPhotos = batch.candidates;
        _dailyPhotoTotal = batch.totalCount;
        _loadingDailyPhotos = false;
      });

      for (final original in batch.candidates) {
        if (!mounted || request != _dailyPhotoRequest) return;
        DailyAlbumCandidate analyzed;
        try {
          analyzed = await _dailyAlbumService.analyze(original);
        } catch (_) {
          analyzed = original.copyWith(hasFace: false);
        }
        if (!mounted || request != _dailyPhotoRequest) return;
        setState(() {
          final index = _dailyPhotos.indexWhere(
            (item) => item.asset.id == original.asset.id,
          );
          if (index >= 0) _dailyPhotos[index] = analyzed;
          _analyzedPhotoCount++;
        });
      }
      if (!mounted || request != _dailyPhotoRequest) return;
      setState(() {
        _dailyPhotos.sort((a, b) {
          final faceCompare = (b.hasFace == true ? 1 : 0).compareTo(
            a.hasFace == true ? 1 : 0,
          );
          if (faceCompare != 0) return faceCompare;
          return a.capturedAt.compareTo(b.capturedAt);
        });
      });
    } on AlbumPermissionDenied {
      if (!mounted || request != _dailyPhotoRequest) return;
      setState(() {
        _loadingDailyPhotos = false;
        _albumPermissionDenied = true;
      });
    } catch (e) {
      if (!mounted || request != _dailyPhotoRequest) return;
      setState(() {
        _loadingDailyPhotos = false;
        _dailyPhotoError = '无法读取当天照片：$e';
      });
    }
  }

  Future<void> _addSelectedDailyPhotos() async {
    if (_addingDailyPhotos || _selectedDailyPhotoIds.isEmpty) return;
    setState(() => _addingDailyPhotos = true);
    var added = 0;
    final scenes = <String>{};
    for (final photo in _dailyPhotos.where(
      (item) => _selectedDailyPhotoIds.contains(item.asset.id),
    )) {
      if (_addedDailyPhotoIds.contains(photo.asset.id)) continue;
      final file = await photo.asset.file;
      if (file == null) continue;
      _media.add(_MediaDraft.picked(XFile(file.path)));
      _addedDailyPhotoIds.add(photo.asset.id);
      if (photo.scene != '成长瞬间') scenes.add(photo.scene);
      added++;
    }
    if (!mounted) return;
    setState(() {
      _addingDailyPhotos = false;
      _selectedDailyPhotoIds.clear();
      for (final scene in scenes) {
        _selectedTags.add(scene);
        if (!_allTagNames.contains(scene)) _allTagNames.add(scene);
      }
    });
    _scheduleDraftSave();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added == 0 ? '没有可添加的照片' : '已添加 $added 张当天照片')),
    );
  }

  Future<void> _pickMedia() async {
    try {
      final files = await ImagePicker().pickMultipleMedia();
      if (files.isEmpty || !mounted) return;
      setState(() {
        _media.addAll(files.map(_MediaDraft.picked));
      });
      _scheduleDraftSave();
      // 大视频提醒：备份与分享会明显变慢。
      for (final x in files) {
        if (MediaService.isVideoName(x.name)) {
          final size = await x.length();
          if (size > 300 * 1024 * 1024 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '视频较大（${(size / 1024 / 1024).toStringAsFixed(0)}MB），备份和分享会更耗时',
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开相册：$e')));
      }
    }
  }

  void _removeMedia(int index) {
    final d = _media[index];
    if (d.existing != null) _removedMediaIds.add(d.existing!.id);
    setState(() => _media.removeAt(index));
    _scheduleDraftSave();
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('新标签'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 12,
              decoration: const InputDecoration(hintText: '例如：第一次、户外、奶奶家'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
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
      _scheduleDraftSave();
    }
  }

  Future<void> _pickMilestone() async {
    final p = context.palette;
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.add_circle_outline_rounded,
                    color: p.accent,
                  ),
                  title: Text(
                    '新建里程碑',
                    style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                    trailing:
                        _milestoneId == m.id
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
        _scheduleDraftSave();
      }
      return;
    }
    if (result != null && mounted) {
      setState(() => _milestoneId = result.isEmpty ? null : result);
      _scheduleDraftSave();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final appState = context.read<AppState>();
    final baby = appState.currentBaby;
    if (baby == null) return;
    if (_content.text.trim().isEmpty && _media.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('写点什么，或添加一张照片吧')));
      return;
    }
    setState(() => _saving = true);
    final saveSpace = appState.importSaveSpace;

    final saved = await runWithProgress<Moment>(
      context,
      task: (report) async {
        final recordId = widget.existing?.id ?? newId();
        final mediaRepo = MediaService.instance;
        final newItems = <MediaItem>[];

        try {
          // 先导入新媒体（失败时尚未改动任何旧数据）
          final kept =
              _media
                  .where((d) => d.existing != null)
                  .map((d) => d.existing!)
                  .toList();
          final picked = _media.where((d) => d.picked != null).toList();
          for (var i = 0; i < picked.length; i++) {
            report('正在处理媒体 ${i + 1}/${picked.length}…');
            final x = picked[i].picked!;
            final isVideo = MediaService.isVideoName(x.name);
            newItems.add(
              await mediaRepo.importMedia(
                sourcePath: x.path,
                type: isVideo ? MediaType.video : MediaType.image,
                recordId: recordId,
                sortOrder: kept.length + i,
                saveSpace: saveSpace,
              ),
            );
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
          final removed =
              widget.existing?.media
                  .where((m) => _removedMediaIds.contains(m.id))
                  .toList() ??
              [];
          await mediaRepo.deleteMediaFiles(
            removed.expand(
              (m) => [m.file, if (m.thumbFile != null) m.thumbFile!],
            ),
          );
          return moment;
        } catch (_) {
          // 失败时清理本次新导入的文件，避免留下孤儿文件
          await mediaRepo.deleteMediaFiles(
            newItems.expand(
              (m) => [m.file, if (m.thumbFile != null) m.thumbFile!],
            ),
          );
          rethrow;
        }
      },
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) {
      _clearDraft();
      appState.bumpData();
      // 今天已有记录，跳过今晚的回顾提醒。
      appState.refreshReminder();
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
              onTap: () {
                setState(() => _favorite = !_favorite);
                _scheduleDraftSave();
              },
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
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 20,
                    color: p.accent,
                  ),
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
          _buildDailyPhotoSuggestions(p, t),
          const SizedBox(height: 20),
          // 正文
          TextField(
            controller: _content,
            maxLines: null,
            minLines: 4,
            autofocus: widget.autofocusContent,
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
                  onSelected: (v) {
                    setState(() {
                      v
                          ? _selectedTags.add(name)
                          : _selectedTags.remove(name);
                    });
                    _scheduleDraftSave();
                  },
                ),
              if (_allTagNames.isEmpty)
                Text('还没有标签，点击右上角"新标签"创建', style: t.bodySmall),
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
                  Icon(Icons.emoji_events_outlined, size: 20, color: p.accent),
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

  Widget _buildDailyPhotoSuggestions(AppPalette p, TextTheme t) {
    final availableCount =
        _dailyPhotos
            .where((p) => !_addedDailyPhotoIds.contains(p.asset.id))
            .length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 20, color: p.accent),
              const SizedBox(width: 8),
              Text('当天照片', style: t.titleMedium),
              const Spacer(),
              if (!_loadingDailyPhotos)
                IconButton(
                  tooltip: '重新查找',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loadDailyPhotos,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
            ],
          ),
          Text('自动查找所选日期拍摄的照片，人脸与场景分析只在手机上进行', style: t.bodySmall),
          if (_loadingDailyPhotos) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('正在读取当天相册…', style: t.bodySmall),
          ] else if (_albumPermissionDenied) ...[
            const SizedBox(height: 12),
            Text('需要照片访问权限，才能自动显示当天照片。', style: t.bodySmall),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: DailyAlbumService.openSettings,
                child: const Text('前往设置'),
              ),
            ),
          ] else if (_dailyPhotoError != null) ...[
            const SizedBox(height: 12),
            Text(_dailyPhotoError!, style: t.bodySmall),
          ] else if (_dailyPhotos.isEmpty) ...[
            const SizedBox(height: 12),
            Text('当天相册里没有找到照片', style: t.bodySmall),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dailyPhotoTotal > _dailyPhotos.length
                        ? '当天共 $_dailyPhotoTotal 张，先展示 ${_dailyPhotos.length} 张'
                        : '当天共 $_dailyPhotoTotal 张',
                    style: t.bodySmall,
                  ),
                ),
                if (_analyzedPhotoCount < _dailyPhotos.length)
                  Text(
                    '识别 $_analyzedPhotoCount/${_dailyPhotos.length}',
                    style: t.bodySmall?.copyWith(color: p.accent),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilterChip(
                  label: const Text('只显示有人'),
                  selected: _faceOnly,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => setState(() => _faceOnly = v),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '人脸识别仅供参考，可手动挑选',
                    style: t.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final section in _groupedDailyPhotos()) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(section.$1, style: t.labelLarge),
              ),
              SizedBox(
                height: 118,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: section.$2.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) =>
                      _dailyPhotoTile(section.$2[index], p),
                ),
              ),
            ],
            if (_faceOnly && _groupedDailyPhotos().isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('暂未识别到有人脸的照片', style: t.bodySmall),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('轻点照片可多选', style: t.bodySmall),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      _selectedDailyPhotoIds.isEmpty ||
                              _addingDailyPhotos ||
                              availableCount == 0
                          ? null
                          : _addSelectedDailyPhotos,
                  icon:
                      _addingDailyPhotos
                          ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(
                            Icons.add_photo_alternate_rounded,
                            size: 18,
                          ),
                  label: Text('添加 ${_selectedDailyPhotoIds.length} 张'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 按上午/下午/晚上分组；组内人脸优先、其次按拍摄时间。
  List<(String, List<DailyAlbumCandidate>)> _groupedDailyPhotos() {
    final photos = _faceOnly
        ? _dailyPhotos.where((x) => x.hasFace == true).toList()
        : _dailyPhotos;
    String sectionOf(DateTime t) {
      if (t.hour >= 5 && t.hour < 12) return '上午';
      if (t.hour >= 12 && t.hour < 18) return '下午';
      return '晚上';
    }

    final groups = <String, List<DailyAlbumCandidate>>{};
    for (final photo in photos) {
      groups.putIfAbsent(sectionOf(photo.capturedAt), () => []).add(photo);
    }
    int rank(DailyAlbumCandidate c) => c.hasFace == true ? 0 : 1;
    final result = <(String, List<DailyAlbumCandidate>)>[];
    for (final name in const ['上午', '下午', '晚上']) {
      final list = groups[name];
      if (list == null || list.isEmpty) continue;
      list.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.capturedAt.compareTo(b.capturedAt);
      });
      result.add((name, list));
    }
    return result;
  }

  Widget _dailyPhotoTile(DailyAlbumCandidate photo, AppPalette p) {
    final selected = _selectedDailyPhotoIds.contains(photo.asset.id);
    final added = _addedDailyPhotoIds.contains(photo.asset.id);
    return GestureDetector(
      onTap: added
          ? null
          : () => setState(() {
                selected
                    ? _selectedDailyPhotoIds.remove(photo.asset.id)
                    : _selectedDailyPhotoIds.add(photo.asset.id);
              }),
      child: SizedBox(
        width: 104,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(photo.thumbnail, fit: BoxFit.cover),
              Positioned(
                left: 5,
                right: 5,
                bottom: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (photo.hasFace == true) ...[
                        const Icon(
                          Icons.face_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          photo.scene,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selected)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: p.accent, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.all(5),
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: p.accent,
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (added)
                Container(
                  color: Colors.black.withValues(alpha: 0.38),
                  alignment: Alignment.center,
                  child: const Text(
                    '已添加',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
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
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: p.accent,
                        size: 26,
                      ),
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
                    ThumbImage(
                      d.existing!.thumbFile ?? d.existing!.file,
                      cacheWidth: 400,
                    )
                  else
                    Image.file(
                      File(d.picked!.path),
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder:
                          (_, __, ___) => Container(color: p.accentSoft),
                    ),
                  if (d.isVideo) const Center(child: VideoBadge()),
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
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
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
