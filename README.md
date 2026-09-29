# iOS 应用合集

## 计划本原生 iOS 版

完全使用 SwiftUI 的本地计划本：每日清单、分类、重复计划、备忘、删除撤销和旧版 JSON 备份迁移。工程位于 [native/Planner](native/Planner/README.md)。

- [Windows 安装与续签说明](docs/ios-install.md)
- [实际验收记录](docs/ios-acceptance.md)
- [云端测试与 IPA 下载](https://github.com/DPclaude/ios/actions/workflows/ios-native.yml)

下载成功构建的 IPA 后，需要由 SideStore 签名安装。手机安装、续签和流畅度以真机验收记录为准。

## 主屏幕网页应用收纳约定

本仓库同时存放可以通过 iPhone Safari「添加到主屏幕」使用的网页应用（PWA）。

- 每个新网页应用使用独立文件夹，例如 `apps/应用英文名/`。
- 各应用的页面、图标、manifest 和 service worker 放在各自目录中，路径和缓存按应用隔离。
- 新增应用时，在下面的应用清单中补充名称和目录。
- 现有“计划本”继续保留在根目录，维持已添加到主屏幕的入口。

| 应用 | 目录 | 说明 |
| --- | --- | --- |
| 计划本网页 | `/`（根目录） | 已有的 iOS 主屏幕计划管理应用 |
| 计划本原生 | `native/Planner/` | SwiftUI iPhone 应用 |

## 计划本网页版

iOS Safari「添加到主屏幕」使用的计划本网页 app，由 GitHub Pages 发布。

### 2026.09.29-3

- 暖白与橙色的卡片界面，深色主题跟随系统。
- 一周日期快速切换、当天完成进度与分类筛选。
- 删除普通任务或重复任务后，7 秒内可点击「撤销」。
- 保留原有任务、备忘、每天重复、自动顺延与备份功能，继续使用原地址和 `planner-v1` 数据。
- 离线缓存与更新只处理计划本资源，避免干扰仓库里其他应用。

回归测试：安装 Node.js 后运行 `node --test tests/planner.test.cjs`，无需安装依赖。

发布网页新版本：修改文件，并把 `index.html` 里的 `VERSION` 和 `version.json` 改成同一个新版本号，推送到 `main`。
约 1–2 分钟后 GitHub Pages 更新，app 顶部会出现「有新版本，点击更新」。
