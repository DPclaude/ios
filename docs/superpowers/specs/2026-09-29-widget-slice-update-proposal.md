# 桌面组件、划切完成与更新：可行方案草案

日期：2026-09-29。状态：已核实现有项目和平台接口；尚未实现。等待用户选择桌面点按与 App 全屏划切的交互取舍。

## 用户目标

iPhone 14 Pro / 用户提供的 iOS 27.0；原生流畅；尽量免费，无 Mac。桌面一眼看计划，完成时像切水果一样有反馈，更新不再手工下载和解压 ZIP。

## 已核实的边界

- WidgetKit 在 iPhone 上提供固定尺寸组件，不提供任意整页尺寸。Extra Large 文档限定 iPadOS、macOS 和相应 visionOS 场景。
- 桌面组件的直接交互通过 AppIntent 的 Button / Toggle 提供；自由拖动轨迹与连续游戏动画应放在 App 内。
- SideStore 提供应用源与 sidestore://install?url= 协议。可以做 App 内检查更新、转交 SideStore 安装；不能承诺 App 自行静默替换签名二进制，也不能把续签称为版本更新。
- 当前仓库只生成需 GitHub 登录且保留 7 天的 Actions 归档。这类链接不适合应用源；更新通道需发布可直接下载的 IPA 和长期可访问的源 JSON。

## 推荐体验（待用户选择）

1. 桌面大组件显示今天、剩余计划和完成进度；可搭配中组件显示进度/备忘，让一页桌面主要用于计划，但保留系统间距与 Dock。
2. 点击进入原生全屏完成页。横向划过任务时显示刀光、卡片分裂/粒子及轻震动；完成仅改变状态，不删除内容，可恢复未完成。普通纵向浏览不触发完成；减少动态效果时使用简短淡出。
3. App 设置新增检查更新及前往 SideStore 更新；首次添加专用源后，后续在 SideStore 点击更新即可。保留同一 Bundle ID 和备份兼容性，覆盖安装后核对数据。

备选：优先直接在桌面操作，用点按完成和短暂状态过渡，放弃桌面自由划切。更新方式相同。

## 需要实现与验证的工程边界

- 现有 PlannerFileStore 是单进程 actor，缓存完整文档。组件与主 App 同时写同一 JSON 会有覆盖风险。需要跨进程事务/锁、重读最新快照，或让组件只读快照并把修改交给 App；不能直接复用当前缓存写入方式。
- 新增 WidgetKit 扩展和数据共享方式，并核对 SideStore 对 App Group entitlement 的重新签名。当前 CODE_SIGNING_ALLOWED=NO 打包不能直接视为已携带扩展需要的权限；检查最终产物。免费账户真机权限与实际组件刷新需设备验证，不能用模拟器结果替代。
- 中文名称继续使用本地化资源，基础签名名称保持 ASCII，防止再次出现 appIdName 拒绝中文。
- 更新源只发布通过验证的包，版本号递增；显示更新失败、网络不可用、SideStore 未安装等状态。源列表不混入仅用于诊断的失败归档。
- 测试覆盖误划/重复完成、动画取消、保存失败、旧数据迁移、组件/主 App 并发更新、每日重复任务、跨午夜、更新版本比较和源 JSON 元数据一致性。

## 官方依据

- https://developer.apple.com/documentation/widgetkit/widgetfamily
- https://developer.apple.com/documentation/widgetkit/widgetfamily/systemextralarge
- https://developer.apple.com/documentation/widgetkit/swiftui-views
- https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- https://docs.sidestore.io/docs/advanced/app-sources
- https://docs.sidestore.io/docs/advanced/url-schema
- https://faq.altstore.io/developers/make-a-source