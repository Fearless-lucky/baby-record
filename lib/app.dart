import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/growth/growth_page.dart';
import 'ui/home/home_page.dart';
import 'ui/settings/baby_edit_page.dart';
import 'ui/settings/lock_page.dart';
import 'ui/settings/settings_page.dart';
import 'ui/timeline/timeline_page.dart';

class BabyApp extends StatefulWidget {
  const BabyApp({super.key});

  @override
  State<BabyApp> createState() => _BabyAppState();
}

class _BabyAppState extends State<BabyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台即上锁（若开启了应用锁）。
    if (state == AppLifecycleState.paused) {
      context.read<AppState>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: '宝宝成长记录',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(state.accentIndex),
      darkTheme: AppTheme.dark(state.accentIndex),
      themeMode: state.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: const Locale('zh'),
      home: state.hasAppLock && state.locked
          ? const LockPage()
          : state.needsOnboarding
              ? const BabyEditPage(isOnboarding: true)
              : const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _index = 0;

  void jumpTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pages = [
      HomePage(onJumpToTab: jumpTo),
      const TimelinePage(),
      const GrowthPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.card,
          border: Border(top: BorderSide(color: p.line, width: 0.8)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              indicatorColor: p.accentSoft,
              elevation: 0,
              height: 62,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? p.accent : p.subInk,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                    color: selected ? p.accent : p.subInk, size: 24);
              }),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: '首页'),
                NavigationDestination(
                    icon: Icon(Icons.view_agenda_outlined),
                    selectedIcon: Icon(Icons.view_agenda_rounded),
                    label: '时间轴'),
                NavigationDestination(
                    icon: Icon(Icons.insights_outlined),
                    selectedIcon: Icon(Icons.insights_rounded),
                    label: '成长'),
                NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: '设置'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
