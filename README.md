# 宝宝成长记录

一本只属于家人的数字成长纪念册（Android / Flutter）。**无账号、无广告、无云端**——所有数据只保存在手机本地。

## 功能

- 宝宝档案（多宝宝）：头像、姓名、昵称、出生日期、年龄与出生天数
- 沉浸式首页：可自定义头图（渐变过渡）、年龄、往年今日对比卡、最新成长、最近记录
- 成长时间轴：文字 + 多照片 + 视频，杂志式拼图布局，藤蔓视觉，分页懒加载
- 记录详情：照片缩放、滑动查看、视频播放、编辑、删除、收藏
- 成长数据：身高/体重/头围记录与趋势图
- 成长里程碑：14 个预置"第一次" + 自定义，可关联照片故事
- 搜索与筛选：关键词、日期、标签、收藏、里程碑
- 日历与回忆：按日查看、往年今日
- 去年今天：沉浸式竖向翻页回顾
- 成长月报：按月汇总，可导出长图分享
- 数据管理：完整备份/恢复（可选 AES 加密）、家庭共享包合并、存储统计与清理
- 隐私：PIN 应用锁、禁用系统云备份（allowBackup=false）
- 外观：深色模式、4 套低饱和主题色

## 隐私与安全

- 不申请存储/相册权限（使用系统相册选择器），不需要网络权限用于任何数据功能
- 数据库 + 照片视频原文件均保存在应用私有目录
- 备份为 zip（`backup.json` + 全部媒体原文件），可设密码加密为 `.babybak`（AES-256-CBC，密钥由密码 SHA-256 派生）
- 应用锁 PIN 以加盐 SHA-256 哈希保存在本地

## 家庭共享

无服务器实时同步不现实也不符合本地私密定位。采用"共享包"模式：
一方 设置 → 家庭共享 → 导出共享包（可加密）→ 微信发给家人；另一方 导入并合并。
记录以 UUID 为主键，重复内容自动跳过，合并不删除任何现有数据。定期互发即可保持一致。

## 架构

```
lib/
  main.dart                入口：系统 UI、媒体路径、全局状态初始化
  app.dart                 MaterialApp（中文化、主题色）+ 底部导航外壳
  theme/app_theme.dart     AppPalette 浅/深色 + 4 套强调色 + 组件主题
  core/utils/              日期、年龄计算
  data/                    models / sqflite(v2, 含 onUpgrade) / repositories
  services/                media_service（导入、缩略图、清理）
                           backup_service（备份/恢复/合并，isolate 压缩解压）
                           backup_utils（可测试的纯函数校验）
  state/app_state.dart     全局状态（当前宝宝、主题、应用锁、数据版本号）
  ui/                      home / timeline / record / growth / milestones
                           search / calendar / settings / common
tool/generate_icons.dart   启动图标生成脚本
test/                      日期/模型/备份校验单元测试
```

关键设计：

- **数据版本号驱动刷新**：写操作后 `AppState.bumpData()`，页面自动重载
- **媒体只存文件名**：时间轴只加载 720px 缩略图，详情页按需读原图
- **备份安全顺序**：校验全部表 → 移入媒体 → 单事务替换数据库 → 清理孤儿文件
- **编辑删除顺序**：先导入新媒体 → 写库成功 → 才删除旧文件；失败清理新文件

## 构建

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

- 正式签名：`android/key.properties` + `android/app/baby_record.keystore`（签名信息仅供家庭内部使用）
- 修改启动图标：替换 `assets/icon/app_icon.png` 后运行 `dart run tool/generate_icons.dart`
- 数据库变更：递增 `DatabaseHelper._version` 并在 `onUpgrade` 追加迁移分支
