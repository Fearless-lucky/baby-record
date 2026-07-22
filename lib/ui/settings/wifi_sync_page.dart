import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/wifi_sync.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// 同一 WiFi 同步：一台手机做主机，其余加入，最终所有人数据取并集。
class WifiSyncPage extends StatefulWidget {
  const WifiSyncPage({super.key});

  @override
  State<WifiSyncPage> createState() => _WifiSyncPageState();
}

enum _Mode { choose, host, join }

class _WifiSyncPageState extends State<WifiSyncPage> {
  _Mode _mode = _Mode.choose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('同一 WiFi 同步')),
      body: switch (_mode) {
        _Mode.host => _HostView(
            onClose: () => setState(() => _mode = _Mode.choose)),
        _Mode.join => _JoinView(
            onClose: () => setState(() => _mode = _Mode.choose)),
        _Mode.choose => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: p.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '所有手机连接家里同一个路由器即可，数据只在局域网内传输，不经过互联网。\n\n'
                        '玩法：一个人点"发起同步"，其他人点"加入同步"；大家都上传完后，发起人点"完成并分发"，每台手机最终拥有所有人的全部记录（并集）。',
                        style: t.bodySmall?.copyWith(color: p.ink),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 我的名字
              _card(
                p,
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded, color: p.accent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('我的名字', style: t.titleMedium),
                          Text(
                            state.authorName.isEmpty
                                ? '未设置（同步与记录的作者标记）'
                                : state.authorName,
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _editName(state),
                      child: Text(
                          state.authorName.isEmpty ? '设置' : '修改'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _modeCard(
                p,
                icon: Icons.wifi_tethering_rounded,
                title: '发起同步',
                subtitle: '这台手机做主机，等待家人加入',
                onTap: state.authorName.isEmpty
                    ? null
                    : () => setState(() => _mode = _Mode.host),
              ),
              const SizedBox(height: 12),
              _modeCard(
                p,
                icon: Icons.sync_rounded,
                title: '加入同步',
                subtitle: '连到家人发起的同步，上传并下载数据',
                onTap: state.authorName.isEmpty
                    ? null
                    : () => setState(() => _mode = _Mode.join),
              ),
              if (state.authorName.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('请先设置"我的名字"，用于标识谁上传了记录',
                      style: t.bodySmall, textAlign: TextAlign.center),
                ),
            ],
          ),
      },
    );
  }

  Future<void> _editName(AppState state) async {
    final controller = TextEditingController(text: state.authorName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('我的名字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 10,
          decoration: const InputDecoration(hintText: '如：妈妈 / 爸爸 / 奶奶'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await state.setAuthorName(name);
    }
  }

  Widget _card(AppPalette p, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  Widget _modeCard(AppPalette p,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback? onTap}) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(
                color: onTap == null ? p.line : p.accent,
                width: onTap == null ? 1 : 1.3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: p.accentSoft, shape: BoxShape.circle),
                child: Icon(icon, color: p.accent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleLarge),
                    const SizedBox(height: 3),
                    Text(subtitle, style: t.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.subInk),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------- 主机视图 ----------------
class _HostView extends StatefulWidget {
  final VoidCallback onClose;
  const _HostView({required this.onClose});

  @override
  State<_HostView> createState() => _HostViewState();
}

class _HostViewState extends State<_HostView> {
  SyncHostSession? _session;
  final List<String> _logs = [];
  List<String> _ips = [];
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
    try {
      _ips = await localIpAddresses();
      final session = SyncHostSession(
        name: state.authorName,
        onLog: (line) {
          if (mounted) setState(() => _logs.add(line));
        },
        onChanged: () {
          if (!mounted) return;
          setState(() {});
          _refreshAppData();
        },
      );
      await session.start();
      if (!mounted) {
        await session.stop();
        return;
      }
      setState(() => _session = session);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _refreshAppData() async {
    final state = context.read<AppState>();
    await state.refreshBabies();
    state.bumpData();
  }

  @override
  void dispose() {
    _session?.stop();
    super.dispose();
  }

  Future<void> _finish() async {
    await _session?.finishUnion();
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final s = _session;
    return PopScope(
      onPopInvokedWithResult: (_, __) => _session?.stop(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null)
            _panel(p,
                child: Text('启动失败：$_error\n请确认已连接 WiFi 后重试',
                    style: t.bodyMedium))
          else if (s == null)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else ...[
            _panel(
              p,
              child: Column(
                children: [
                  Text('让家人在手机上点"加入同步"，并输入同步码',
                      style: t.bodySmall),
                  const SizedBox(height: 14),
                  Text(s.code,
                      style: t.displayLarge?.copyWith(
                          fontSize: 44, letterSpacing: 12)),
                  const SizedBox(height: 10),
                  Text(
                    _ips.isEmpty ? '未检测到局域网 IP' : '本机 IP：${_ips.join('  ')}',
                    style: t.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text('端口 ${s.port}', style: t.labelSmall),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _panel(
              p,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('同步日志',
                            style: t.titleMedium),
                      ),
                      Text('已接收 ${s.receivedCount} 份',
                          style: t.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final line in _logs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('· $line', style: t.bodySmall),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!_finished)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      s.receivedCount > 0 ? _finish : null,
                  icon: const Icon(Icons.merge_type_rounded),
                  label: Text(s.receivedCount > 0
                      ? '全部上传完毕，完成并分发'
                      : '等待家人上传…'),
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: p.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('并集已分发。等家人都显示"同步完成"后再结束。',
                          style: t.bodyMedium),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await _session?.stop();
                    widget.onClose();
                  },
                  child: const Text('结束同步'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _panel(AppPalette p, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

/// ---------------- 加入方视图 ----------------
class _JoinView extends StatefulWidget {
  final VoidCallback onClose;
  const _JoinView({required this.onClose});

  @override
  State<_JoinView> createState() => _JoinViewState();
}

class _JoinViewState extends State<_JoinView> {
  List<SyncHostInfo> _hosts = [];
  bool _discovering = true;
  SyncHostInfo? _selected;
  final _ipController = TextEditingController();
  final _portController =
      TextEditingController(text: kSyncBasePort.toString());
  final _codeController = TextEditingController();
  final List<String> _logs = [];
  bool _syncing = false;
  SyncJoinResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() => _discovering = true);
    final hosts = await SyncClient.discover();
    if (!mounted) return;
    setState(() {
      _hosts = hosts;
      _discovering = false;
      if (hosts.isNotEmpty) _selected ??= hosts.first;
    });
  }

  Future<void> _sync() async {
    final ip = _selected?.ip ?? _ipController.text.trim();
    final port = _selected?.port ??
        int.tryParse(_portController.text.trim()) ??
        kSyncBasePort;
    final code = _codeController.text.trim();
    if (ip.isEmpty) {
      setState(() => _error = '请选择或输入主机 IP');
      return;
    }
    if (code.length != 4) {
      setState(() => _error = '请输入主机上的 4 位同步码');
      return;
    }
    if (port < 1 || port > 65535) {
      setState(() => _error = '请输入有效的主机端口');
      return;
    }
    setState(() {
      _syncing = true;
      _error = null;
      _logs.clear();
    });
    try {
      final result = await SyncClient().sync(
        hostIp: ip,
        port: port,
        code: code,
        myName: context.read<AppState>().authorName,
        log: (line) {
          if (mounted) setState(() => _logs.add(line));
        },
      );
      if (!mounted) return;
      final state = context.read<AppState>();
      await state.refreshBabies();
      state.bumpData();
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    if (_result != null) {
      final r = _result!;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 30),
          Icon(Icons.check_circle_outline_rounded,
              size: 72, color: p.accent),
          const SizedBox(height: 20),
          Text('同步完成', style: t.displaySmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            '已从「${r.hostName}」获得并集数据：\n上传 ${r.uploadedMedia} 个文件 · 下载 ${r.downloadedMedia} 个文件\n新增 ${r.newBabies} 个档案、${r.newMoments} 条记录',
            style: t.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.onClose,
              child: const Text('完成'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _panel(
          p,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('选择主机', style: t.titleMedium)),
                  if (_discovering)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2)),
                  IconButton(
                    tooltip: '重新搜索',
                    onPressed: _syncing ? null : _discover,
                    icon: Icon(Icons.refresh_rounded,
                        size: 20, color: p.accent),
                  ),
                ],
              ),
              if (_hosts.isEmpty && !_discovering)
                Text('没有自动搜索到主机（可能被路由器隔离），\n可手动输入主机屏幕上显示的 IP。',
                    style: t.bodySmall),
              for (final h in _hosts)
                RadioListTile<SyncHostInfo>(
                  contentPadding: EdgeInsets.zero,
                  value: h,
                  groupValue: _selected,
                  onChanged: _syncing
                      ? null
                      : (v) => setState(() {
                            _selected = v;
                            _ipController.clear();
                          }),
                  title: Text(h.name),
                  subtitle: Text('${h.ip}:${h.port}'),
                ),
              if (_selected == null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ipController,
                        enabled: !_syncing,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: '主机 IP', hintText: '如 192.168.1.5'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _portController,
                        enabled: !_syncing,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '端口'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _codeController,
                enabled: !_syncing,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                    labelText: '同步码', hintText: '主机屏幕上的 4 位数字'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: TextStyle(color: p.favorite, fontSize: 13),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        if (!_syncing)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sync,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('开始同步'),
            ),
          )
        else
          _panel(
            p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )),
                for (final line in _logs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('· $line', style: t.bodySmall),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _panel(AppPalette p, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}
