# 原生计划本验收记录

目标设备：iPhone 14 Pro / iOS 27.0（用户提供，尚未连接真机验收）。

## 1.1.0 云端验证

验证日期：2026-09-29。构建 27；源码 `cfbc2a408619b58b7a9c5a2048f2c8b3ab017c5c`。Xcode 26.6；iPhone 17 Pro 模拟器 / iOS 26.5。

| 项目 | 结果 |
|---|---|
| 业务、存储、组件投影、更新校验 | 19 项通过 |
| App 状态与保存 | 13 项通过，包括重复完成保护、跨日撤销、保存失败不发布未保存组件数据 |
| 原生界面 | 4 项通过，包括横向划切、撤销、连续添加、编辑、深色和大字体 |
| 更新源生成 | 2 项 Node 测试通过 |
| 真机 Release 编译和打包 | arm64 App 与 Widget 扩展成功；英文签名名称、中文显示名称、App Group 签名元数据、ZIP 完整性检查通过 |
| 版本发布 | App、组件、更新清单和 SideStore 源均为 1.1.0；公开 IPA 和 JSON 链接可访问 |

[测试与打包成功记录](https://github.com/DPclaude/ios/actions/runs/36528615241/job/109277236047) · [1.1.0 发布页](https://github.com/DPclaude/ios/releases/tag/native-v1.1.0) · [小白说明](ios-beginner-guide.md)

公开 IPA 已下载复核：805296 字节；SHA256 `c1ed63a8f8a302b0797e1a036b9912ac4319c0bf0ba21b12b8018a611e04a31f`，与构建 27 一致。App 与扩展均为 1.1.0（27）。公开的 latest 更新源及清单已核对版本、Bundle ID、下载地址和文件大小。

安装包是供 SideStore 重新签名的 IPA。内嵌临时签名仅携带请求的 App Group 元数据，不是 Apple 分发签名。保留 `com.dpclaude.planner` Bundle ID 和原私有存储位置，不执行数据迁移或清空。组件只读取主 App 成功保存后发布的原子快照。

## 代码审查与回归

独立审查发现并修复：缺少 snapshot 的分类参数；动画取消后未释放界面锁；跨日撤销的普通任务未顺延。版本发布校验另拦截了默认 Info.plist 版本号未继承配置的问题，现显式绑定 App 与扩展的版本号、构建号。

之前的 [构建 19](https://github.com/DPclaude/ios/actions/runs/36522015078) 已验证英文 Planner 签名名称，解决 appIdName 使用中文的配置问题；本版延续该配置。

## 真机仍需验证

| 项目 | 状态 |
|---|---|
| 个人 Apple 账户在 SideStore 签名安装，保留组件扩展 | 待用户手机确认 |
| 覆盖安装后原计划、重复规则和备忘保留 | 待确认；安装前导出备份 |
| 免费账户 App Group 重签名与组件数据同步 | 待确认；代码读取 SideStore 重写后的 ALTAppGroups |
| 桌面组件点击进入划切页、刷新速度、震动和手感 | 待确认；WidgetKit 刷新由系统调度 |
| SideStore 添加更新源及后续覆盖更新 | 公开链接已校验，手机操作待确认 |
| 自动续签真正触发、刷新有效期 | 未启用／未验证；需要手机配置与实际执行 |
| iOS 27.0 兼容性、iPhone 14 Pro 性能 | 未做真机测量；不声称固定 120fps |

模拟器通过和公开发布不等于已经替用户完成手机安装、账号授权或自动续签。

## 发布维护

macOS 的 Release 与 release 路径可能指向同一目录；发行附件现独立写入 build/distribution，使用单独的必需归档。缺失附件将使验证失败。首次发布由 GitHub 页面创建发行版、自动任务上传测试过的 IPA；创建发行版的 token 权限不足时不扩大权限或填写个人令牌，保留构建归档并通过已授权 GitHub 页面完成。
`native-v1.1.0` 的自动源码快照仍指向网页主分支；GitHub 集成拒绝改写标签，未扩大 token 权限。发行说明明确链接本 IPA 实际使用的原生源码 `cfbc2a408619b58b7a9c5a2048f2c8b3ab017c5c/native/Planner`。安装包、更新源及其校验结果不受标签源码快照影响。
