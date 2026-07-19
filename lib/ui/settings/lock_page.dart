import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// 应用锁界面：PIN 数字键盘。
class LockPage extends StatefulWidget {
  const LockPage({super.key});

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  String _input = '';
  bool _error = false;

  void _type(String digit) {
    if (_input.length >= 6) return;
    setState(() {
      _input += digit;
      _error = false;
    });
    if (_input.length >= 4) _verify();
  }

  void _delete() {
    if (_input.isEmpty) return;
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  void _verify() {
    final state = context.read<AppState>();
    if (state.verifyPin(_input)) {
      state.unlock();
    } else {
      setState(() {
        _input = '';
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 76,
              height: 76,
              decoration:
                  BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.lock_outline_rounded,
                  size: 34, color: p.accent),
            ),
            const SizedBox(height: 24),
            Text('宝宝成长记录', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text(_error ? '密码不正确，请重试' : '输入密码解锁',
                style: t.bodySmall?.copyWith(
                    color: _error ? p.favorite : p.subInk)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _input.length
                          ? p.accent
                          : p.accentSoft,
                    ),
                  ),
              ],
            ),
            const Spacer(flex: 2),
            _keypad(p),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _keypad(AppPalette p) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          for (final row in keys)
            Row(
              children: [
                for (final k in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: AspectRatio(
                        aspectRatio: 1.5,
                        child: k.isEmpty
                            ? const SizedBox.shrink()
                            : k == 'del'
                                ? IconButton(
                                    onPressed: _delete,
                                    icon: Icon(
                                        Icons.backspace_outlined,
                                        color: p.subInk),
                                  )
                                : Material(
                                    color: p.card,
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    child: InkWell(
                                      onTap: () => _type(k),
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: p.line),
                                          borderRadius:
                                              BorderRadius.circular(
                                                  16),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(k,
                                            style: TextStyle(
                                                fontSize: 22,
                                                fontWeight:
                                                    FontWeight.w500,
                                                color: p.ink)),
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 设置 / 修改 PIN 的弹窗流程。返回是否成功设置。
Future<bool> showPinSetup(BuildContext context) async {
  final first = await showDialog<String>(
    context: context,
    builder: (ctx) => const _PinEntryDialog(
        title: '设置密码', hint: '输入 4-6 位数字密码'),
  );
  if (first == null || !context.mounted) return false;
  final second = await showDialog<String>(
    context: context,
    builder: (ctx) =>
        const _PinEntryDialog(title: '确认密码', hint: '再次输入密码'),
  );
  if (second == null || !context.mounted) return false;
  if (first != second) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('两次输入不一致，请重新设置')));
    return false;
  }
  await context.read<AppState>().setPin(first);
  return true;
}

/// 验证 PIN 的弹窗（用于关闭应用锁前确认）。返回是否验证通过。
Future<bool> showPinVerify(BuildContext context) async {
  final state = context.read<AppState>();
  final pin = await showDialog<String>(
    context: context,
    builder: (ctx) =>
        const _PinEntryDialog(title: '验证密码', hint: '输入当前密码'),
  );
  if (pin == null || !context.mounted) return false;
  final ok = state.verifyPin(pin);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('密码不正确')));
  }
  return ok;
}

class _PinEntryDialog extends StatefulWidget {
  final String title;
  final String hint;

  const _PinEntryDialog({required this.title, required this.hint});

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        obscureText: true,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final pin = _controller.text.trim();
            if (pin.length < 4) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码至少 4 位数字')));
              return;
            }
            Navigator.pop(context, pin);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
