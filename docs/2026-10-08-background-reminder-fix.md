# Android 后台提醒缺陷修复记录

## 验证约定

依据：本次用户要求。已有任务不能因启动、进入或退出应用推迟；后台调度不依赖 Activity；前台继续抑制自动通知；主题、时段、间隔、冷却和通知权限规则保持。

范围：应用恢复/暂停、冷启动、原生 AlarmManager、独立 WorkManager Engine、下一次任务接续、普通错误恢复。系统强行停止、OEM 杀后台和系统精确闹钟限制不能由模拟测试证明已解决。

确认的范围内缺陷：

1. 生命周期以及启动重复 reconcile，应用服务强制完整间隔，重置原生闹钟；短暂访问也改变待触发时间。
2. 闹钟 MethodChannel 只在 MainActivity 注册，WorkManager 的独立 Engine 没有通道，精确闹钟续调度退回 WorkManager。
3. 后台任务异常返回 true，下一次任务未创建时既没有接续也没有重试。
4. WorkManager Android 桥接使用 `initialDelay.inSeconds`，将正的小数秒向下截断。后台接续可能提前醒来，在间隔边界尚未到达时再次创建零延迟任务。模拟器日志实际出现过这种紧邻执行；现在向上取整到秒，保持零延迟为零。

补充发现：当前 workmanager_android 0.10.9 将 Dart ExistingWorkPolicy.update 映射为 APPEND_OR_REPLACE。因此后台接续不会因为该策略取消正在运行的 Worker；它是现有正确行为。但 UI 每次注册也会向回退链追加任务，应区分保留、替换和接续。

矩阵：

| 入口 | 不变量 | 证据要求 |
|---|---|---|
| 短暂进入、退出、冷启动 | 保留有效任务及到期时间 | 生命周期回归、平台 KEEP/保存的原生到期时间 |
| 独立 Worker Engine | 无 Activity 时通道仍可调度与取消 | Android 集成测试 |
| 后台持续运行 | 实际主题内容自动提交并继续安排 | Android 系统任务/通知记录，至少两条内容 |
| 进程回收 | 原生注册任务不依赖 Flutter UI 进程 | Android 回收进程后观察执行 |
| 原生不可用 | WorkManager 接续不取消自己 | 回退策略回归及 Android 执行 |
| 后台异常 | 不以成功吞掉中断链路 | Worker 返回重试回归 |
| 前台到期 | 不提交通知，不消耗提醒历史 | 执行服务回归及 Android 执行 |

旧测试中“暂停后从退出时刻等待完整间隔”的预期，被本次用户明确要求替代；更新该测试，不恢复旧行为来保留绿灯。

RED 证据：暂停时原实现注册 60 秒而剩余应约 2 秒；Worker 异常返回 true 而应 false；异常闹钟桥接未注册回退任务。

## 实际修复

- 生命周期、权限状态刷新和启动恢复使用 KEEP。原生端重新注册保存的未来到期时间，WorkManager 保留已有工作；不再统一强制从当前时刻等待完整间隔。
- 设置变更继续 REPLACE，并保留保存设置后首次等待一个间隔的原有语义。后台 Worker 使用 APPEND_OR_REPLACE 接续；切换回原生闹钟时不取消正在执行的 Worker。
- 将原生 receiver 和通知图标移到已有本地 `android_process_state` 插件。receiver 的完整类名、Manifest 声明、PendingIntent 身份和通知通道不变。闹钟 MethodChannel 在每个 Engine 的 FlutterPlugin 注册，使用 applicationContext；不再依赖 Activity。
- 后台评估/续调度失败返回 false 请求 WorkManager 重试，保留故障记录。平台桥接异常仍能安排回退任务。
- 回退延迟向上取整，避免插件截断导致提前执行。

生产文件：

```text
lib/app/app_shell.dart
lib/app/app_services.dart
lib/features/settings/reminder_settings_page.dart
lib/runtime/reminder_runtime_bootstrap.dart
lib/runtime/reminder_scheduler.dart
lib/runtime/reminder_worker.dart
lib/runtime/exact_reminder_alarm_port.dart
lib/runtime/android_reminder_alarm_port.dart
android/app/src/main/kotlin/com/wly112488/kaoyan_review/MainActivity.kt
packages/android_process_state/android/src/main/kotlin/com/wly112488/android_process_state/AndroidProcessStatePlugin.kt
packages/android_process_state/android/src/main/kotlin/com/wly112488/kaoyan_review/ReminderAlarmReceiver.kt
packages/android_process_state/android/src/main/res/drawable/ic_stat_review.xml
```

后两个文件从 app 模块移动。未改变数据库 schema、主题筛选、内容排序、间隔、冷却、时段、通知权限规则或前台抑制。

## 验证结果（2026-10-08）

- `flutter test --concurrency=1 --reporter=expanded`：135 个测试通过。
- `flutter analyze`：No issues found。通过同一 checkout 的 `T:\` 映射运行，规避工具处理中文路径的问题。
- `flutter build apk --debug`：通过，普通 `lib/main.dart` 应用；不是 integration_test 入口 APK。
- 独立 Worker Engine 通道测试：修复前实际 Android 运行得到 `MissingPluginException`；修复后通过。额外启用 `REQUIRE_HEADLESS_EXACT_ALARM=true` 验证 schedule 返回 true，并成功取消注册的闹钟。
- Android API 36 x86_64 模拟器后台流程：同一主题下两个启用内容，调用生产 CRUD 和设置保存服务，使用真实 AppShell。先在前台等到 OS 任务执行并验证未发送，再 HOME；第一条发送后短暂重进并再次 HOME。主机只切换 Activity 和准备测试权限，未手动运行 Worker、广播 receiver 或安排提醒。

| 实际路径 | 三次后台提交（设备 UTC） | 内容顺序 | 结果 |
|---|---|---|---|
| 原生闹钟 | 10:36:56.738 / 10:37:56.744 / 10:38:56.762 | 1 → 2 → 1 | 通过，系统活动通知编号与内容一致 |
| WorkManager 回退 | 11:05:01.606 / 11:06:02.391 / 11:07:48.074 | 3 → 4 → 3（同一主题的两条内容） | 通过，系统活动通知编号与内容一致 |

回退第三次比一分钟目标晚约 46 秒；这证明后台接续，不证明 WorkManager 精确执行。集成测试检查三次在观察窗口内发生、间隔不少于设定值、内容编号和系统通知一致，不要求系统保证一分钟准点。

### 普通 APK 的进程回收验证

使用上一流程持久化的两条内容安装普通应用 APK，正常打开并 HOME；用 `am kill` 模拟后台进程回收，没有 `force-stop`。

```text
11:10:13.608 原生注册下一次：11:11:13.568
11:10:28.201 HOME 后保持相同到期时间：11:11:13.568
11:10:30.112 ActivityManager Killing 6810 ... kill background
11:11:13.580 ActivityManager Start proc 6911 ... for broadcast ReminderAlarmReceiver
11:11:14.099 submitted review notification itemId=4
11:12:14.104 submitted review notification itemId=3
```

未重新打开 Activity。系统还在两次通知之间冻结该进程，再由闹钟解冻执行。已观察并截图：桌面顶部横幅显示数据库里的“实际主题复习内容 fallback 2”。这是模拟器的可见横幅证据，不是华为/OPPO 真机结论。

本机证据保存在 `.codex-tooling/`：`native-flow.log`、`fallback-flow.log`、`headless-scheduled.log`、`process-recovery.log`、`process-recovery-processes.log`、`process-recovery-first-notification.png`、`full-test-final.log`、`analyze.log`、`build-debug.log`。

## 复现命令与边界

```powershell
flutter test integration_test/android_headless_alarm_bridge_test.dart -d emulator-5554 --no-uninstall --reporter=expanded
# 精确闹钟权限已允许时，可额外加 --dart-define=REQUIRE_HEADLESS_EXACT_ALARM=true
flutter test integration_test/android_background_reminder_flow_test.dart -d emulator-5554 --no-uninstall --reporter=expanded
# 拒绝精确闹钟权限验证回退时，加 --dart-define=REMINDER_FALLBACK=true
```

后台流程测试在 `REMINDER_TEST_PREPARE` 等待通知权限和匹配的精确闹钟权限；`REMINDER_TEST_HOME`、`REMINDER_TEST_REENTER`、`REMINDER_TEST_EXIT_BRIEF` 标记要求主机/操作者依次 HOME、短暂打开 MainActivity、HOME。不会由测试主机直接触发通知。

本次只有模拟器连接，无华为 NOH-AN01 / OPPO PGBM10 真机。本次未验证真实 OEM 省电策略、锁屏/Doze 长期运行、重启恢复或权限撤销过程。`am kill` 是后台进程回收模拟，不等同于 OEM 的所有杀后台方式。强行停止、闹钟权限撤销、系统空闲限频和通知/横幅设置仍可能限制执行或展示；不能承诺所有手机一分钟准点或每条必有横幅。
