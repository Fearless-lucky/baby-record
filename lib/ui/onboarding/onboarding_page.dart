import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class OnboardingPage extends StatefulWidget {
  /// 从设置页再次查看时，结束后返回上一页，不改动首次启动状态。
  final bool replay;

  const OnboardingPage({super.key, this.replay = false});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    _TutorialPageData(
      icon: Icons.auto_stories_rounded,
      eyebrow: '欢迎来到宝宝成长记录',
      title: '把长大，轻轻收进时光里',
      description: '一本只属于家人的数字成长纪念册。\n从第一个微笑开始，留住每一个平凡又珍贵的今天。',
      points: ['无账号，打开就能记录', '支持多个宝宝档案', '温柔的时间轴与回忆页'],
    ),
    _TutorialPageData(
      icon: Icons.edit_note_rounded,
      eyebrow: '记录日常',
      title: '文字、照片与视频，都有它的位置',
      description: '选择记录日期后，会自动展示相册里当天拍摄的照片，勾选即可加入时间轴。',
      points: ['本地识别人脸与大致场景', '按日期、标签和关键词查找', '收藏瞬间并生成月报长图'],
    ),
    _TutorialPageData(
      icon: Icons.insights_rounded,
      eyebrow: '看见成长',
      title: '每一次变化，都值得被认真对待',
      description: '记录身高、体重和头围，查看成长趋势；也可以收藏第一次翻身、第一声爸爸妈妈等里程碑。',
      points: ['成长数据趋势图', '14 个预置里程碑与自定义事件', '往年今日带你重温旧时光'],
    ),
    _TutorialPageData(
      icon: Icons.family_restroom_rounded,
      eyebrow: '安心珍藏',
      title: '数据在手机里，回忆在家人之间',
      description: '所有记录默认保存在本机。你可以定期备份，也可以让家人在同一 WiFi 下交换彼此的新记录。',
      points: ['可选密码加密备份', '同一 WiFi 下的家庭合并', '应用锁保护私密回忆'],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (widget.replay) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await context.read<AppState>().completeTutorial();
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  Text('宝宝成长记录',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: Text(widget.replay ? '关闭' : '跳过'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) =>
                    _TutorialContent(data: _pages[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: i == _index ? 24 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: i == _index ? p.accent : p.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _next,
                      icon: Icon(last
                          ? Icons.auto_stories_rounded
                          : Icons.arrow_forward_rounded),
                      label: Text(last
                          ? (widget.replay ? '完成' : '创建宝宝档案')
                          : '继续'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialContent extends StatelessWidget {
  final _TutorialPageData data;

  const _TutorialContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 8),
      child: Column(
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: p.accentSoft,
              shape: BoxShape.circle,
              border: Border.all(color: p.line),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 25,
                  right: 30,
                  child: Icon(Icons.auto_awesome_rounded,
                      size: 18, color: p.accent.withValues(alpha: 0.55)),
                ),
                Icon(data.icon, size: 62, color: p.accent),
              ],
            ),
          ),
          const SizedBox(height: 34),
          Text(
            data.eyebrow,
            style: t.labelSmall?.copyWith(
              color: p.accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(data.title,
              style: t.displaySmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(data.description,
              style: t.bodyMedium?.copyWith(color: p.subInk),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.card,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                for (var i = 0; i < data.points.length; i++) ...[
                  if (i > 0) Divider(height: 20, color: p.line),
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: p.accentSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_rounded,
                            size: 17, color: p.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(data.points[i], style: t.bodyMedium)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialPageData {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final List<String> points;

  const _TutorialPageData({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.points,
  });
}
