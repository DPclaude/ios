# 计划本 · 原生 iOS

SwiftUI 原生界面，纯 Swift 业务规则，本地离线数据。最低 iOS 17，目标设备 iPhone 14 Pro / iOS 27.0。

## 工程

- `Sources/PlannerCore`：日期、普通任务、每日重复、顺延、备份兼容。
- `Sources/PlannerStore`：串行 actor、原子存储、导入恢复副本。
- `App`：SwiftUI 视图和主线程状态；文件操作在存储 actor 执行。
- `AppTests` / `UITests`：状态回归与 iOS 界面验收。

## 构建与测试

Windows 可编辑代码；编译 iOS 使用 GitHub Actions 的标准 macOS 环境。

在 macOS，先选择 Xcode 26.6，然后在此目录运行：

```sh
swift test
bash scripts/ci-test.sh
bash scripts/build-ipa.sh
```

测试脚本固定 XcodeGen 2.46.0 的源代码提交，生成 Xcode 工程与原生图标，再启动 iOS 模拟器测试。生成的 Xcode 工程和构建结果不提交到 Git。

产物 `build/Planner-unsigned.ipa` **尚未使用 Apple 证书签名**，需交给 SideStore 签名安装。代码更新需要新的 IPA；刷新签名不会更新代码。

## 数据

应用沙盒 `Application Support/Planner/planner.json` 为带格式版本的存储文件。外部导入导出使用与网页相同的 `tasks/notes/repeats/repeatDone` JSON。

覆盖导入前保存 `before-import.json`，可在设置中明确确认恢复。此副本仍在 App 沙盒内，卸载会失去它；重要备份请导出到“文件”。

读写失败会提示未保存，不以空数据覆盖损坏文件。返回前台时会按当前本地日历日顺延未完成的旧任务。

## 使用与验收

见 [安装与续签](../../docs/ios-install.md) 和 [真机验收记录](../../docs/ios-acceptance.md)。测试模式通过 `--uitesting` 使用单独目录；`--reset-data` 只清理该测试目录，永不清理正常数据。

免费安装和自动刷新存在 Apple 签名有效期及 iOS 后台执行限制。App 不收集账户密码，不提供自我续签机制，也不包含统计或追踪 SDK。
