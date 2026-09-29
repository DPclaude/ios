# iPhone 安装、迁移与自动续签

第一次使用？先看[《计划本：小白使用说明》](ios-beginner-guide.md)，从安装到每天怎么用，一步一步操作。

适用设备：iPhone 14 Pro / iOS 27.0。代码与安装包的完成状态以 GitHub Actions 实际运行结果和 `ios-acceptance.md` 为准。

## 1. 先保留旧数据

1. 打开原来的网页版计划本，在设置中选择“导出备份”。
2. 保存 JSON 到 iPhone 的“文件”，记住位置。不要先移除原网页入口。
3. 安装原生 App 后，进入设置 → 导入备份，选这个 JSON。
4. 检查预览中的普通任务、重复规则及备忘数量，确认后导入。
5. 对照旧版检查几个日期、重复完成状态与备忘，再额外导出一份原生备份。

网页和原生 App 的沙盒不同，不能直接读取对方数据。导入会覆盖原生 App 当前内容；应用会先保存一个导入前恢复副本。副本也会随卸载消失。

## 2. 获取安装包

在仓库的 [Actions](https://github.com/DPclaude/ios/actions/workflows/ios-native.yml) 中打开成功的 Native iOS 运行，在 Artifacts 下载 `Planner-native-构建号`，解压得到 `Planner-unsigned.ipa`。开发阶段分支为 `codex/native-ios`。

这是待签名的真机安装包，不是模拟器 App。请交给 SideStore 安装；直接在“文件”中点击并不能安装。不要把测试失败运行的日志归档当成安装包。

## 3. 免费安装 SideStore

使用 [SideStore 官方安装指南](https://docs.sidestore.io/docs/installation/prerequisites)。当前官方流程支持 Windows 辅助首次安装，包含 Apple 设备驱动、安装器、配对以及 LocalDevVPN。以官方页面和当前工具界面为准，不从不明网站购买证书。

需要你在自己设备／官方工具里完成：连接 iPhone、信任电脑、Apple 账户登录及双重认证、必要的开发者模式和本地 VPN 授权。不要将密码、验证码或配对文件发到聊天、仓库或 GitHub Actions。

安装完成后，在 SideStore 中导入 `Planner-unsigned.ipa`，用你的个人账户签名。免费账户通常最多同时安装 3 个这类应用，SideStore 本身占用一个；已有侧载 App 时先查看可用名额，不擅自删除已有应用。

### 你尚未安装 SideStore：首次操作顺序

1. Windows 先按[官方前置条件](https://docs.sidestore.io/docs/installation/prerequisites)安装 iTunes 驱动和 iloader；手机从 [App Store 安装 LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044)。
2. 用数据线连接 iPhone，解锁并在手机上信任这台电脑。
3. 打开 iloader，在工具中自行登录 Apple 账户，选择这台 iPhone，再选 `Install SideStore (Stable)`。
4. 在手机“设置 → 通用 → VPN 与设备管理”中打开对应开发者账户，按系统提示信任并重启。
5. 在“隐私与安全性 → 开发者模式”按提示开启并重启；连接 LocalDevVPN，再打开 SideStore，使用同一账户登录。
6. 在 `My Apps` 中先刷新 SideStore 本身，确认成功后安装计划本 IPA。

这些步骤来自 [SideStore 当前安装说明](https://docs.sidestore.io/docs/installation/install)。若出现证书替换或登录错误，先读清具体影响；当前手机上的 iOS 27.0 兼容性仍需实际安装验证，不能由云端模拟器推断。

## 4. 验证续签，然后启用自动刷新

1. 按官方要求连接 Wi-Fi，打开本地 VPN。
2. 在 SideStore 手动刷新计划本，确认到期时间延长；重开计划本，数据应仍在。
3. 打开 SideStore 需要的后台刷新设置。
4. 查看当前版本提供的“快捷指令”刷新动作；若有，创建每天执行的个人自动化，开启所需 VPN 后刷新 SideStore 及计划本。动作名依安装版本确认，不使用来源不明的共享快捷指令。
5. 在相同条件下手动运行这条快捷指令一次，再观察一次真正的定时触发及锁屏执行结果，将记录填写到验收表。
6. 当前版本没有快捷指令动作时，使用官方后台刷新功能；不要把未执行的定时提醒称作续签。

签名通常 7 天有效。每天尝试刷新能留出重试时间，但网络、Apple 服务、配对、VPN 和 iOS 后台限制仍可能导致失败。长期离线或未成功刷新会过期。

续签失败先打开 SideStore 查看报错并重试；必要时用 Windows 重新配对或签名。优先按相同账户和 Bundle ID 覆盖安装，先导出可访问的数据，不把卸载 App 当作第一步。

## 5. 软件更新

新功能需要下载新的 IPA 并覆盖安装；保持同一个 Apple 账户和 App 身份。签名刷新只延长有效期，不会自动安装新版本。

## 官方依据

- [SideStore 前置条件](https://docs.sidestore.io/docs/installation/prerequisites)
- [SideStore FAQ：后台刷新与免费账户限制](https://docs.sidestore.io/docs/faq)
- [Apple 免费账户与开发者会员](https://developer.apple.com/support/compare-memberships/)
- [GitHub 标准托管运行器](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
