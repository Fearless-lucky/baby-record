import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repositories.dart';
import '../services/reminder_service.dart';

/// 全局应用状态：宝宝列表、当前宝宝、主题模式、主题色、应用锁、数据版本号。
class AppState extends ChangeNotifier {
  static const _keyBaby = 'currentBabyId';
  static const _keyTheme = 'themeMode';
  static const _keyAccent = 'accentIndex';
  static const _keySaveSpace = 'importSaveSpace';
  static const _keyPinHash = 'appLockPinHash';
  static const _keyLastBackup = 'lastBackupAt';
  static const _keyAuthor = 'authorName';
  static const _keyTutorialSeen = 'tutorialSeen';
  static const _keyReminderMode = 'reminderMode';
  static const _keyDailyPhotoLimit = 'dailyPhotoLimit';

  final BabyRepository _babies = BabyRepository();

  List<Baby> babies = [];
  String? currentBabyId;
  ThemeMode themeMode = ThemeMode.system;
  int accentIndex = 0;
  bool importSaveSpace = false;
  DateTime? lastBackupAt;

  /// 记录者名字（如"妈妈"），用于新记录的作者标记与同步身份。
  String authorName = '';

  /// 首次启动教程是否已经完成。已有数据的老用户默认视为已完成。
  bool tutorialSeen = false;

  /// 每日回顾提醒：0=从不，1=每天，2=仅周末。
  int reminderMode = 0;

  /// 当天照片推荐每次最多展示数量：0 表示全部。
  int dailyPhotoLimit = 60;

  String? _pinHash;

  /// 应用锁当前是否处于锁定状态。
  bool locked = false;

  /// 数据版本号：任何写操作后自增，驱动各页面刷新。
  int version = 0;

  bool _initialized = false;
  bool get initialized => _initialized;

  Baby? get currentBaby {
    if (babies.isEmpty) return null;
    for (final b in babies) {
      if (b.id == currentBabyId) return b;
    }
    return babies.first;
  }

  bool get needsOnboarding => babies.isEmpty;

  bool get needsTutorial => !tutorialSeen;

  bool get hasAppLock => _pinHash != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    currentBabyId = prefs.getString(_keyBaby);
    themeMode = ThemeMode.values[prefs.getInt(_keyTheme) ?? 0];
    accentIndex = prefs.getInt(_keyAccent) ?? 0;
    importSaveSpace = prefs.getBool(_keySaveSpace) ?? false;
    _pinHash = prefs.getString(_keyPinHash);
    locked = hasAppLock;
    authorName = prefs.getString(_keyAuthor) ?? '';
    final backupMs = prefs.getInt(_keyLastBackup);
    if (backupMs != null) {
      lastBackupAt = DateTime.fromMillisecondsSinceEpoch(backupMs);
    }
    reminderMode = prefs.getInt(_keyReminderMode) ?? 0;
    dailyPhotoLimit = prefs.getInt(_keyDailyPhotoLimit) ?? 60;
    await refreshBabies();
    final savedTutorialState = prefs.getBool(_keyTutorialSeen);
    tutorialSeen = savedTutorialState ?? babies.isNotEmpty;
    if (savedTutorialState == null && tutorialSeen) {
      await prefs.setBool(_keyTutorialSeen, true);
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> refreshBabies() async {
    babies = await _babies.all();
    if (babies.isNotEmpty && babies.every((b) => b.id != currentBabyId)) {
      currentBabyId = babies.first.id;
      await _saveCurrentBaby();
    }
    notifyListeners();
  }

  Future<void> setCurrentBaby(String id) async {
    currentBabyId = id;
    await _saveCurrentBaby();
    bumpData();
  }

  Future<void> _saveCurrentBaby() async {
    final prefs = await SharedPreferences.getInstance();
    if (currentBabyId != null) {
      await prefs.setString(_keyBaby, currentBabyId!);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, mode.index);
    notifyListeners();
  }

  Future<void> setAccentIndex(int index) async {
    accentIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAccent, index);
    notifyListeners();
  }

  Future<void> setImportSaveSpace(bool value) async {
    importSaveSpace = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySaveSpace, value);
    notifyListeners();
  }

  Future<void> setAuthorName(String name) async {
    authorName = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthor, authorName);
    notifyListeners();
  }

  Future<void> completeTutorial() async {
    tutorialSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTutorialSeen, true);
    notifyListeners();
  }

  Future<void> setReminderMode(int mode) async {
    reminderMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReminderMode, mode);
    notifyListeners();
    await ReminderService.instance.refresh(mode, currentBaby?.id);
  }

  Future<void> setDailyPhotoLimit(int limit) async {
    dailyPhotoLimit = limit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDailyPhotoLimit, limit);
    notifyListeners();
  }

  /// 当天已有记录时跳过今晚的提醒；数据变化后调用。
  Future<void> refreshReminder() =>
      ReminderService.instance.refresh(reminderMode, currentBaby?.id);

  // ---------------- 应用锁 ----------------

  static String _hashPin(String pin) =>
      sha256.convert(utf8.encode('baby_record_lock:$pin')).toString();

  Future<void> setPin(String pin) async {
    _pinHash = _hashPin(pin);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPinHash, _pinHash!);
    locked = false;
    notifyListeners();
  }

  Future<void> clearPin() async {
    _pinHash = null;
    locked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPinHash);
    notifyListeners();
  }

  bool verifyPin(String pin) => _hashPin(pin) == _pinHash;

  void unlock() {
    locked = false;
    notifyListeners();
  }

  void lock() {
    if (hasAppLock) {
      locked = true;
      notifyListeners();
    }
  }

  // ---------------- 备份 ----------------

  Future<void> markBackupDone() async {
    lastBackupAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastBackup, lastBackupAt!.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// 任意数据变更后调用，通知所有页面刷新。
  void bumpData() {
    version++;
    notifyListeners();
  }
}
