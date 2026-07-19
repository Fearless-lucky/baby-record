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

/// 添加 / 编辑宝宝档案；也用于首次启动的引导页。
class BabyEditPage extends StatefulWidget {
  final Baby? existing;
  final bool isOnboarding;

  const BabyEditPage(
      {super.key, this.existing, this.isOnboarding = false});

  @override
  State<BabyEditPage> createState() => _BabyEditPageState();
}

class _BabyEditPageState extends State<BabyEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _nickname;
  late DateTime _birth;
  String? _avatarFile;
  String? _headerFile;
  String? _newAvatarSource;
  String? _newHeaderSource;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _nickname = TextEditingController(text: e?.nickname ?? '');
    _birth = AppDateUtils.day(e?.birthDate ?? DateTime.now());
    _avatarFile = e?.avatarFile;
    _headerFile = e?.headerFile;
  }

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x != null && mounted) setState(() => _newAvatarSource = x.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开相册：$e')));
      }
    }
  }

  Future<void> _pickHeader() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x != null && mounted) setState(() => _newHeaderSource = x.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开相册：$e')));
      }
    }
  }

  Future<void> _pickBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '出生日期',
    );
    if (picked != null) setState(() => _birth = AppDateUtils.day(picked));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty && _nickname.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写宝宝的名字')));
      return;
    }
    setState(() => _saving = true);
    final state = context.read<AppState>();
    try {
      String? avatar = _avatarFile;
      if (_newAvatarSource != null) {
        avatar = await MediaService.instance.importAvatar(_newAvatarSource!);
        if (_avatarFile != null && _avatarFile != avatar) {
          await MediaService.instance.deleteAvatar(_avatarFile);
        }
      }
      String? header = _headerFile;
      if (_newHeaderSource != null) {
        header = await MediaService.instance.importHeader(_newHeaderSource!);
        if (_headerFile != null && _headerFile != header) {
          await MediaService.instance.deleteAvatar(_headerFile);
        }
      }
      final repo = BabyRepository();
      String id;
      if (widget.existing == null) {
        id = newId();
        await repo.insert(Baby(
          id: id,
          name: _name.text.trim(),
          nickname: _nickname.text.trim(),
          birthDate: _birth,
          avatarFile: avatar,
          headerFile: header,
          createdAt: DateTime.now(),
        ));
      } else {
        id = widget.existing!.id;
        await repo.update(widget.existing!.copyWith(
          name: _name.text.trim(),
          nickname: _nickname.text.trim(),
          birthDate: _birth,
          avatarFile: () => avatar,
          headerFile: () => header,
        ));
      }
      await state.refreshBabies();
      if (widget.existing == null || widget.isOnboarding) {
        await state.setCurrentBaby(id);
      }
      state.bumpData();
      if (!mounted) return;
      if (!widget.isOnboarding) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final hasAvatar =
        _newAvatarSource == null && _avatarFile != null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isOnboarding,
        title: Text(widget.isOnboarding
            ? '欢迎'
            : widget.existing == null
                ? '添加宝宝'
                : '编辑档案'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          if (widget.isOnboarding) ...[
            Text('这是一本只属于家人的成长纪念册',
                style: t.displaySmall),
            const SizedBox(height: 8),
            Text('所有数据只保存在这台手机上。先为宝宝建立一个档案吧。',
                style: t.bodySmall),
            const SizedBox(height: 28),
          ],
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  if (_newAvatarSource != null)
                    CircleAvatar(
                      radius: 52,
                      backgroundImage: ResizeImage(
                          FileImage(File(_newAvatarSource!)),
                          width: 300),
                    )
                  else
                    BabyAvatar(
                      avatarFile: hasAvatar ? _avatarFile : null,
                      name: _nickname.text.isNotEmpty
                          ? _nickname.text
                          : _name.text,
                      radius: 52,
                    ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: p.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.card, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_outlined,
                          size: 15, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _name,
            maxLength: 20,
            decoration: const InputDecoration(
                labelText: '姓名', hintText: '宝宝的大名'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nickname,
            maxLength: 20,
            decoration: const InputDecoration(
                labelText: '昵称（可选）', hintText: '平时怎么叫 TA'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickBirth,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: p.card,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.cake_outlined, color: p.accent, size: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('出生日期', style: t.labelSmall),
                      const SizedBox(height: 2),
                      Text(AppDateUtils.full(_birth),
                          style: t.bodyMedium),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 首页头图
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.card,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: _newHeaderSource != null
                        ? Image.file(File(_newHeaderSource!),
                            fit: BoxFit.cover)
                        : _headerFile != null &&
                                MediaPaths.avatarBase != null
                            ? Image.file(
                                File(MediaPaths.avatar(_headerFile!)),
                                fit: BoxFit.cover)
                            : Container(
                                color: p.accentSoft,
                                child: Icon(Icons.image_outlined,
                                    color: p.accent),
                              ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('首页照片', style: t.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        _newHeaderSource != null || _headerFile != null
                            ? '已自定义，首页顶部展示这张照片'
                            : '未设置，自动使用最新照片',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _pickHeader,
                  child: const Text('选择'),
                ),
                if (_headerFile != null || _newHeaderSource != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _newHeaderSource = null;
                      _headerFile = null;
                    }),
                    child: Text('重置',
                        style: TextStyle(color: p.subInk)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(widget.isOnboarding ? '开始记录' : '保存'),
            ),
          ),
        ],
      ),
    );
  }
}

