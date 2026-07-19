import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/backup_service.dart';
import '../../services/media_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../common/widgets.dart';
import '../onboarding/onboarding_page.dart';
import 'baby_edit_page.dart';
import 'lock_page.dart';
import 'wifi_sync_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  StorageStats? _stats;
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
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    final stats = await MediaService.instance.stats(baby.id);
    if (mounted) setState(() => _stats = stats);
  }

  /// 备份前询问是否加密；返回 (确认, 密码)。
  Future<(bool, String?)> _askBackupOptions() async {
    final passwordController = TextEditingController();
    var encrypt = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('创建备份'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('加密备份'),
                subtitle: const Text('设置密码保护照片与数据'),
                value: encrypt,
                onChanged: (v) => setState(() => encrypt = v),
              ),
              if (encrypt)
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  maxLength: 32,
                  decoration: const InputDecoration(
                      labelText: '备份密码', hintText: '恢复时需要输入'),
                ),
              const SizedBox(height: 8),
              const Text('备份包含全部数据与照片视频原文件，完成后可分享到微信/网盘保存。',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始备份'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return (false, null);
    if (encrypt) {
      final pwd = passwordController.text.trim();
      if (pwd.length < 4) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('密码至少 4 位，已创建未加密备份')));
        }
        return (true, null);
      }
      return (true, pwd);
    }
    return (true, null);
  }

  Future<void> _backup({bool shareAfter = true}) async {
    final (confirmed, password) = await _askBackupOptions();
    if (!confirmed || !mounted) return;
    final path = await runWithProgress<String>(
      context,
      task: (report) => BackupService.instance
          .createBackup(password: password, onProgress: report),
    );
    if (path == null || !mounted) return;
    await context.read<AppState>().markBackupDone();
    if (!mounted) return;
    if (shareAfter) {
      final share = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('备份完成'),
          content: const Text(
              '备份已生成。建议立即把它发送到微信"文件传输助手"、邮箱或网盘保存，防止手机丢失或卸载后数据无法找回。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('稍后')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('立即分享'),
            ),
          ],
        ),
      );
      if (share == true && mounted) {
        try {
          await BackupService.instance.shareBackup(path);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('分享失败：$e')));
          }
        }
      }
    }
  }

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入备份密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: '创建备份时设置的密码'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    final state = context.read<AppState>();
    if (state.babies.isNotEmpty) {
      final ok = await confirmDanger(
        context,
        title: '从备份恢复？',
        message: '当前手机上的全部数据（宝宝档案、记录、照片）将被备份内容完全替换，此操作不可撤销。',
        confirmText: '继续恢复',
      );
      if (!ok || !mounted) return;
    }
    final summary = await runWithProgress<RestoreSummary?>(
      context,
      task: (report) => BackupService.instance
          .restoreBackup(askPassword: _askPassword, onProgress: report),
    );
    if (summary == null || !mounted) return;
    await _afterDataReload(state);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复完成'),
        content: Text(
            '已恢复 ${summary.babies} 个宝宝档案、${summary.moments} 条记录、${summary.mediaFiles} 个媒体文件。'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
        ],
      ),
    );
  }

  Future<void> _importShare() async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入共享包'),
        content: const Text(
            '将家人发来的共享包合并到本机。只会新增内容，不会删除或覆盖你现有的记录；重复的内容会自动跳过。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('选择文件'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final summary = await runWithProgress<MergeSummary?>(
      context,
      task: (report) => BackupService.instance
          .importAndMerge(askPassword: _askPassword, onProgress: report),
    );
    if (summary == null || !mounted) return;
    await _afterDataReload(state);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('合并完成'),
        content: Text(
            '新增 ${summary.newBabies} 个宝宝档案、${summary.newMoments} 条记录、${summary.newMedia} 个媒体文件。\n\n提示：请家人也导入你最近导出的共享包，双方数据就能保持一致。'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
        ],
      ),
    );
  }

  Future<void> _afterDataReload(AppState state) async {
    MediaPaths.reset();
    await MediaPaths.ensure();
    await state.refreshBabies();
    state.bumpData();
  }

  Future<void> _deleteBaby(Baby baby) async {
    final ok = await confirmDanger(
      context,
      title: '删除宝宝档案？',
      message:
          '「${baby.displayName}」的全部记录、照片、视频和成长数据都会被删除，且不可恢复。建议先备份。',
    );
    if (!ok || !mounted) return;
    final files = await BabyRepository().delete(baby.id);
    await MediaService.instance.deleteMediaFiles(files);
    await MediaService.instance.deleteAvatar(baby.avatarFile);
    if (baby.headerFile != null) {
      await MediaService.instance.deleteAvatar(baby.headerFile);
    }
    if (!mounted) return;
    final state = context.read<AppState>();
    await state.refreshBabies();
    state.bumpData();
  }

  Future<void> _toggleAppLock(bool enable) async {
    final state = context.read<AppState>();
    if (enable) {
      final ok = await showPinSetup(context);
      if (!ok || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('应用锁已开启')));
    } else {
      final ok = await showPinVerify(context);
      if (!ok || !mounted) return;
      await state.clearPin();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('应用锁已关闭')));
    }
  }

  Future<void> _cleanOrphans() async {
    final (count, freed) = await runWithProgress<(int, int)>(
          context,
          task: (_) => MediaService.instance.cleanOrphanFiles(),
        ) ??
        (0, 0);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(count == 0
            ? '没有可清理的文件'
            : '已清理 $count 个未使用文件，释放 ${(freed / 1024 / 1024).toStringAsFixed(1)} MB')));
    _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final state = context.watch<AppState>();
    final baby = state.currentBaby;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 60),
        children: [
          // 当前宝宝
          if (baby != null) ...[
            _card(
              p,
              child: Column(
                children: [
                  Row(
                    children: [
                      BabyAvatar(
                          avatarFile: baby.avatarFile,
                          name: baby.displayName,
                          radius: 30),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(baby.displayName,
                                style: t.headlineMedium),
                            const SizedBox(height: 3),
                            Text(
                              '${AppDateUtils.full(baby.birthDate)}出生 · ${baby.ageText()}',
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '编辑档案',
                        icon: Icon(Icons.edit_outlined, color: p.accent),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    BabyEditPage(existing: baby))),
                      ),
                    ],
                  ),
                  if (state.babies.length > 1) ...[
                    const Divider(height: 24),
                    for (final b
                        in state.babies.where((b) => b.id != baby.id))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: BabyAvatar(
                            avatarFile: b.avatarFile,
                            name: b.displayName,
                            radius: 16),
                        title: Text('切换到「${b.displayName}」',
                            style: t.bodyMedium),
                        trailing: Icon(Icons.swap_horiz_rounded,
                            color: p.subInk),
                        onTap: () => state.setCurrentBaby(b.id),
                      ),
                  ],
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const BabyEditPage())),
                        icon: const Icon(Icons.person_add_alt_rounded,
                            size: 18),
                        label: const Text('添加宝宝'),
                      ),
                      TextButton.icon(
                        onPressed: () => _deleteBaby(baby),
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: p.favorite),
                        label: Text('删除档案',
                            style: TextStyle(color: p.favorite)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 家庭共享
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardTitle(t, '家庭共享'),
                const SizedBox(height: 4),
                Text(
                  '没有服务器，也不会上传任何数据。同一 WiFi 下可直接互相同步（并集）；不在同一网络时，用共享包互传。记录会标记是谁上传的。',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                _actionTile(p, t,
                    icon: Icons.wifi_rounded,
                    title: '同一 WiFi 同步',
                    subtitle: state.authorName.isEmpty
                        ? '先设置"我的名字"，再与家人同步'
                        : '以「${state.authorName}」身份同步 · 自动合并并集',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WifiSyncPage()))),
                _actionTile(p, t,
                    icon: Icons.ios_share_rounded,
                    title: '导出共享包',
                    subtitle: '与完整备份相同，可设置密码',
                    onTap: _backup),
                _actionTile(p, t,
                    icon: Icons.download_rounded,
                    title: '导入并合并',
                    subtitle: '合并家人发来的共享包，不删除现有数据',
                    onTap: _importShare),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 数据与备份
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardTitle(t, '数据与备份'),
                const SizedBox(height: 4),
                Text(
                  '所有数据仅保存在本机。卸载应用或更换手机前，请务必先备份。',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                _actionTile(p, t,
                    icon: Icons.cloud_upload_outlined,
                    title: '立即备份',
                    subtitle: state.lastBackupAt == null
                        ? '还没有备份过'
                        : '上次备份：${AppDateUtils.full(state.lastBackupAt!)}',
                    onTap: _backup),
                _actionTile(p, t,
                    icon: Icons.cloud_download_outlined,
                    title: '从备份恢复',
                    subtitle: '完全替换本机数据（.zip 或加密的 .babybak）',
                    onTap: _restore),
                _actionTile(p, t,
                    icon: Icons.sd_storage_outlined,
                    title: '存储占用',
                    subtitle: _stats == null
                        ? '统计中…'
                        : '${_stats!.totalText} · ${_stats!.momentCount} 条记录 · ${_stats!.imageCount} 张照片 · ${_stats!.videoCount} 个视频',
                    onTap: _loadStats),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _cleanOrphans,
                        icon: const Icon(
                            Icons.cleaning_services_outlined,
                            size: 17),
                        label: const Text('清理未使用文件',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('节省存储空间', style: t.titleMedium),
                  subtitle: Text('新导入的照片以 2048px 保存（原图仍在系统相册）',
                      style: t.bodySmall),
                  value: state.importSaveSpace,
                  onChanged: state.setImportSaveSpace,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 隐私
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardTitle(t, '隐私'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('应用锁', style: t.titleMedium),
                  subtitle: Text(
                      state.hasAppLock ? '已开启，打开应用需要密码' : '开启后打开应用需要输入密码',
                      style: t.bodySmall),
                  value: state.hasAppLock,
                  onChanged: _toggleAppLock,
                ),
                const SizedBox(height: 4),
                Text(
                  '忘记密码只能通过清除应用数据重置（数据会丢失，请定期备份）。',
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 外观
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardTitle(t, '外观'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (mode, label) in const [
                      (ThemeMode.system, '跟随系统'),
                      (ThemeMode.light, '浅色'),
                      (ThemeMode.dark, '深色'),
                    ])
                      Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: _segmentOption(
                            p,
                            label: label,
                            selected: state.themeMode == mode,
                            onTap: () => state.setThemeMode(mode),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('主题色', style: t.bodySmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < kAccents.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: GestureDetector(
                          onTap: () => state.setAccentIndex(i),
                          child: Column(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: kAccents[i].light,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: state.accentIndex == i
                                        ? p.ink
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: state.accentIndex == i
                                    ? const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 20)
                                    : null,
                              ),
                              const SizedBox(height: 5),
                              Text(kAccents[i].name,
                                  style: t.labelSmall
                                      ?.copyWith(fontSize: 10.5)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 关于
          _card(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardTitle(t, '关于'),
                const SizedBox(height: 6),
                Text('瑜见时光 1.2.1', style: t.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  '一本只属于家人的数字成长纪念册。\n无账号 · 无广告 · 无云端，数据完全属于你自己。',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 10),
                _actionTile(
                  p,
                  t,
                  icon: Icons.menu_book_outlined,
                  title: '使用教程',
                  subtitle: '重新查看记录、成长、同步与备份说明',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OnboardingPage(replay: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentOption(AppPalette p,
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? p.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: selected ? p.accent : p.line),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? p.accent : p.subInk,
          ),
        ),
      ),
    );
  }

  Widget _card(AppPalette p, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }

  Widget _cardTitle(TextTheme t, String title) =>
      Text(title, style: t.titleLarge);

  Widget _actionTile(AppPalette p, TextTheme t,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: p.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.subInk),
          ],
        ),
      ),
    );
  }
}
