# 计划本原生 iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 iPhone 14 Pro / iOS 27.0 交付完全原生、可迁移旧数据的计划本 IPA，并完成免费安装与续签配置验证。

**Architecture:** SwiftUI App 使用纯 Swift 业务模块和串行文件存储模块。业务数据按日期派生到原生列表，文件编码与读写不占用 UI 主线程；GitHub Actions 执行测试及未签名 IPA 构建，SideStore 在设备上签名。

**Tech Stack:** Swift 6、SwiftUI、Observation、Foundation、XCTest、Swift Package Manager、XcodeGen 2.46.0、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-09-29-native-ios-design.md`（用户已批准）。

## Global Constraints

- 完全原生 SwiftUI；不使用 WKWebView、HTML 或 JavaScript 运行计划功能。
- 部署目标 iOS 17.0，目标设备 iPhone 14 Pro / iOS 27.0；主界面中文，显示名“计划本”。
- Bundle ID 固定 `com.dpclaude.planner`；首个原生版本 `1.0.0`，构建号使用 CI run number。
- 网页基线 `906a21d`；网页数据及入口保留，原生工程位于 `native/Planner/`。
- 四分类编号为 0 默认、1 工作、2 私事、3 学习；完成时间为 Unix 毫秒，日期为本地公历 `YYYY-MM-DD`。
- 本地数据，无账户后台、付费 SDK、云同步、推送、小组件或自定义重复周期。
- 删除撤销窗口 7 秒，重复完成记录保留 90 天；普通历史和日记不自动清理。
- 普通数据集 1,000 个普通任务和 30 个重复规则；压力数据集 10,000 个普通任务、当天 300 项。
- 云端选择标准 `macos-26` 和 `/Applications/Xcode_26.6.app/Contents/Developer`，先验证路径和版本再构建；不静默改用其他 SDK。
- 2026-09-29 核实的镜像含 Xcode 26.6、iOS 26.5 模拟器。此为构建基线，不冒称已模拟 iOS 27；iOS 27 必须由用户真机验收。
- CI 产物为待 SideStore 签名的 IPA，禁止在仓库、日志及构建产物中保存 Apple 密码、配对文件和用户备份。
- 不承诺固定 120fps、永久免签或永远自动续签成功；没有实测证据的步骤明确标记未验证。

## Review Focus

1. 旧 JSON 的 ID 不是 UUID，且字段可能缺省：保留有效数据，非法类型明确拒绝；由任务 1 的兼容性测试覆盖。
2. 正在编辑备忘时切换日期／前后台：旧内容不能写到新日期；由任务 3 的日期绑定测试覆盖。
3. 快速编辑并发保存、导入期间旧保存晚到：最终磁盘内容必须是最新状态；由任务 2 的 generation/revision 测试覆盖。
4. 重复任务删除后撤销，同时新增普通任务：撤销不覆盖期间其他变更；由任务 1、3 的局部撤销测试覆盖。
5. 手机时间或时区变化及重启：顺延幂等、原有日历日不发生 UTC 偏移；由任务 1 日期测试和任务 5 生命周期测试覆盖。

## 文件布局

- `native/Planner/Package.swift`：PlannerCore、PlannerStore 两个 library 和各自测试 target，macOS 下运行核心测试。
- `native/Planner/Sources/PlannerCore/{Models,Day,PlannerDocument,BackupCodec}.swift`：纯 Foundation 值类型与业务规则。
- `native/Planner/Sources/PlannerStore/PlannerFileStore.swift`：actor、格式封装、版本与原子写入。
- `native/Planner/Tests/PlannerCoreTests/{DayTests,DocumentTests,BackupTests}.swift` 与 `Fixtures/legacy.json`。
- `native/Planner/Tests/PlannerStoreTests/StoreTests.swift`：临时目录、失败与乱序保存测试。
- `native/Planner/App/{PlannerApp,PlannerViewModel}.swift`：入口、生命周期、UI 状态和保存队列。
- `native/Planner/App/Views/{PlannerDayView,WeekStrip,TaskRow,TaskEditor,DailyNoteView,SettingsView}.swift`：按交互职责分文件。
- `native/Planner/App/BackupDocument.swift`：系统 JSON 导入导出衔接。
- `native/Planner/App/Resources/Assets.xcassets/`：强调色和 AppIcon；复用现有图标图形制作所需尺寸。
- `native/Planner/AppTests/PlannerViewModelTests.swift`：App target 的状态与生命周期测试。
- `native/Planner/UITests/PlannerUITests.swift`：系统界面冒烟测试与截图。
- `native/Planner/project.yml`：固定 target、scheme、版本、资源与本地 package。
- `native/Planner/scripts/{ci-test,build-ipa}.sh`：macOS 测试和打包入口。
- `.github/workflows/ios-native.yml`：云端验证、编译、产物。
- `native/Planner/README.md`、`docs/ios-install.md`、`docs/ios-acceptance.md`：开发、安装和实际验收记录；根 README 添加入口。
- `.gitignore`：仅增加 Swift/Xcode 构建产物规则。

## 执行与环境规则

实施开始时使用 using-git-worktrees 检查并准备隔离分支；通过 App 的 worktree 工具操作，设计和计划必须一并带入执行目录。不要重置用户已有改动。每项任务在有运行环境的地方完成红灯／绿灯验证；当前 Windows 无 Swift 与 Xcode，不将文本检查冒充编译通过。

最初即准备任务 1 所需的核心测试工作流，使用 `swift test --package-path native/Planner` 在 macOS 跑测试。待 UI 加入后扩展为完整工作流。若 Git 凭证不可用，可利用已登录 GitHub 的浏览器提交该分支的文件／触发工作流；不得读取浏览器凭证或把 Apple 账户放进 CI。访问确实不足时，列出缺少的仓库操作权限，不伪造云端运行结果。

每个任务先完成指定测试再提交该任务文件；仅在实际测试失败与新改动需要时重跑。使用有意义的阶段提交，不为每个小编辑单独提交。

### Task 1: 旧数据兼容的原生业务模块

**Files:** `Package.swift`、`Sources/PlannerCore/`、`Tests/PlannerCoreTests/`，以及 `.github/workflows/ios-native.yml` 的初始核心测试 job。

**Interfaces:**
- `Day: RawRepresentable, Codable, Hashable, Comparable, Sendable`，`init?(rawValue: String)` 校验严格公历日期；`static func today(now: Date, timeZone: TimeZone) -> Day`；`func adding(days: Int, timeZone: TimeZone) -> Day`。
- `PlannerTask` 保存旧普通任务字段；`RepeatRule` 保存旧规则字段；均为 Codable/Equatable/Sendable。
- `PlannerDocument: Codable, Equatable, Sendable`，属性 `tasks: [PlannerTask]`、`notes: [String:String]`、`repeats: [RepeatRule]`、`repeatDone: [String:[String]]`。
- `TaskReference: Hashable, Sendable`：`.task(String)` 或 `.repeating(ruleID: String, day: Day)`，UI 标识区分任务和规则。
- `DaySnapshot: Equatable, Sendable`：`open`、`completed` 为 `[TaskItem]`，`totalCount`、`completedCount` 为 Int；`TaskItem` 包含 reference、text、cat、done、rolled、order。
- `PlannerDocument.snapshot(day: Day, category: Int?) -> DaySnapshot`；变更方法：`add(text: String, category: Int, day: Day, id: String)`、`toggle(_ reference: TaskReference, now: Date)`、`edit(_ reference: TaskReference, text: String, category: Int)`、`pin(taskID: String)`、`moveToNextDay(taskID: String, timeZone: TimeZone)`、`convertToRepeat(taskID: String, ruleID: String)`、`cancelRepeat(ruleID: String, day: Day, taskID: String, now: Date)`、`rollover(today: Day, timeZone: TimeZone)`。
- `remove(_ reference: TaskReference) -> RemovedItem?` 和 `restore(_ removed: RemovedItem, today: Day, timeZone: TimeZone)`；RemovedItem 保存项目及恢复需要的规则完成状态，不是整份文档。
- `BackupCodec.decode(_ data: Data) throws -> PlannerDocument`；`encode(_ document: PlannerDocument) throws -> Data`，兼容网页 JSON，不输出内部存储 envelope。

- [ ] 写 `DayTests`：`2026-09-30 + 1 = 2026-10-01`、`2026-12-31 + 1 = 2027-01-01`、`2028-02-28 + 1 = 2028-02-29`；拒绝 `2026-02-30`；America/Los_Angeles 夏令时切换前后加一天仍为下一日。
- [ ] 写 `BackupTests`：非 UUID ID `old-task-1` 保留；仅有 tasks 时其余集合为空；正常备份 encode/decode 相等；拒绝重复 ID、无效日期、cat=4、字符串 done；删除规则遗留的完成引用不影响有效记录。
- [ ] 写 `DocumentTests`：旧未完成任务顺延且二次执行不变化；完成历史／未来不变；过滤不改变总进度；普通与重复完成互不影响；重复转换保留当日完成；取消规则留下指定日期普通任务；排序稳定；删除→新增→撤销后新增项目仍在；仅清理 90 天以前的重复完成记录。
- [ ] 用已定义模型 fixture 写断言，例如 `XCTAssertEqual(decoded.tasks.first?.id, "old-task-1")`、`XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(document)), document)`；提交测试检查点并在 macOS 运行 `swift test --package-path native/Planner`，记录预期未实现接口的失败。
- [ ] 实现上述业务接口，默认值与旧版一致，纯 Swift Foundation 无平台 UI 依赖；再运行相同测试，必须全通过。
- [ ] 提交 `feat: add native planner data model and legacy migration`，记录云端运行链接。

### Task 2: 不丢数据的串行文件存储

**Files:** `Sources/PlannerStore/PlannerFileStore.swift`、`Tests/PlannerStoreTests/StoreTests.swift`、Package 的 store target。

**Interfaces:**
- `StoreSnapshot: Sendable` 包含 `document: PlannerDocument`、`generation: UUID`、`revision: UInt64`。
- `PlannerFileStore` actor：`init(directory: URL)`；`load() throws -> StoreSnapshot`；`save(_ snapshot: StoreSnapshot) throws`；`replace(with document: PlannerDocument) throws -> StoreSnapshot`；`recoverPreviousImport() throws -> StoreSnapshot`。
- 私有 Codable envelope 包含 schemaVersion=1、generation、revision、document。恢复／导入产生新 generation，普通修改递增 revision；拒绝旧 generation 或较低 revision，不能静默报告旧保存成功。
- `load` 仅在文件不存在时新建空文档，损坏或不支持版本抛错。主文件 `planner.json`，覆盖导入前副本 `before-import.json`。

- [ ] 写 `StoreTests`：保存后新实例重载相等；先 revision=2 再 revision=1 不得覆盖；replace 后旧 generation 保存拒绝；损坏文件原始字节不变；非法导入不写盘；副本写入失败时主文件不变；恢复副本能取回导入前数据。
- [ ] 运行 `swift test --package-path native/Planner --filter StoreTests` 确认失败，再实现 actor 与 `.atomic` 写入；actor 文件操作中不插入导致重入乱序的 await。
- [ ] `replace` 先校验和编码，再保存恢复副本，再原子写主文件，全部成功才返回新 snapshot；错误向调用方传播。
- [ ] 重跑 store 与 core 测试，确认全部通过；提交 `feat: persist planner data with ordered atomic saves`。

### Task 3: 原生状态、保存状态与生命周期

**Files:** `App/PlannerViewModel.swift`、`AppTests/PlannerViewModelTests.swift`、`project.yml`、App 的最小入口，CI 的 App 单元测试阶段。

**Interfaces:**
- `@MainActor @Observable final class PlannerViewModel`：`init(store: PlannerFileStore, now: @escaping () -> Date, timeZone: @escaping () -> TimeZone)`；`load() async`；`select(day: Day)`；`select(category: Int?)`；`perform(_ action: PlannerAction)`；`updateNote(_ text: String, for day: Day)`；`flush() async`；`refreshCalendar() async`；`retrySave() async`；`undoDelete(now: Date)`。
- `PlannerAction` case 与任务 1 的用户操作一一对应，含 ID、日期等显式参数，不在 view 中直接改文档。
- 可观察状态：`selectedDay`、`category`、`snapshot: DaySnapshot`、`saveState: SaveState`、`loadError: String?`、`undoAvailable: Bool`、`document: PlannerDocument`（只读）；SaveState 为 saved/saving/failed(String)。
- UI 变更立即更新内存，唯一保存协调器依次发送快照，维护 generation/revision；成功回执只对仍匹配的版本显示已保存。
- `prepareImport(data: Data) async throws -> ImportPreview`、`confirmImport(_ preview: ImportPreview) async throws`、`exportData() async throws -> Data`；ImportPreview 包含候选文档及任务/规则/备忘数量。解码/编码在 store actor 中执行，需为 store 增加 `decodeBackup`/`encodeBackup` 转发方法。

- [ ] 用临时目录写状态测试：备忘“甲”在 9/29 输入后切到 9/30，flush 后甲仍属 9/29；load 失败禁止编辑空文档覆盖旧盘；连续完成多项最终全部保存；保存失败可重试；导入确认前 flush，确认失败不改 UI；旧回执不能把新修改标成已保存。
- [ ] 写撤销测试：注入时钟删除后第 6 秒可撤销，第 8 秒不可；撤销不抹掉期间新增任务。写日期刷新测试：后台跨午夜后只顺延未完成任务。
- [ ] XcodeGen 定义 `Planner`、`PlannerAppTests`、`PlannerUITests` targets，scheme `Planner`，Swift 6 严格并发，本地 package 链接 core/store；生成工程并用任务 5 的 `ci-test.sh` 执行失败测试。
- [ ] 实现状态模型和串行保存协调器；备忘防抖 350ms，切日期先提交旧日期快照；导入暂停修改并排空旧保存队列，不依赖 actor 的调度先后来保证版本顺序。
- [ ] 所有测试通过后提交 `feat: coordinate native planner state and reliable saving`。

### Task 4: 系统原生界面与备份流程

**Files:** `App/PlannerApp.swift`、`App/Views/`、`App/BackupDocument.swift`、`App/Resources/Assets.xcassets/`、`UITests/PlannerUITests.swift`。

**Interfaces:**
- `PlannerDayView(model: PlannerViewModel)` 用 NavigationStack/List 呈现日期、进度、未完成/已完成区域与当天备忘；view body 只消费已派生 snapshot。
- `WeekStrip(selected: Day, onSelect: (Day) -> Void)`；`TaskRow(item: TaskItem, onToggle: () -> Void, onEdit: () -> Void)`。
- `TaskEditor` 接收编辑草稿和保存/删除等回调，使用系统 sheet/Form/FocusState；支持新任务、分类、日期和每日重复。
- `DailyNoteView(day: Day, text: String, onChange: (String, Day) -> Void)` 明确携带编辑日期，防止切日串写。
- `SettingsView(model: PlannerViewModel)` 使用 fileImporter/fileExporter/ShareLink；BackupDocument 使用 JSON UTType。

- [ ] 先写 UI 冒烟测试：使用隔离目录与固定日期的 launch arguments；新增“测试计划”→完成→编辑→删除→撤销→关开后仍在；筛选、下一日、今天、连续新增流程可操作。
- [ ] 增加界面状态断言：重复编辑显示“影响整条重复规则”；导入展示数量并要求覆盖确认；加载失败可见恢复提示，新增入口禁用；保存失败显示“尚未保存”并有重试/导出。
- [ ] 云端运行 UI 测试确认未实现的交互失败；随后实现视图、系统日期选择器、原生侧滑动作和编辑面板，不添加自绘滚动容器。
- [ ] 使用系统橙色 accent、SF Symbols、语义字体与背景；交互点击区域至少 44pt，VoiceOver 能读出任务与完成状态。分类在大字体下可横向滚动，不挤压成不可点的小标签。
- [ ] 完成状态轻触反馈与局部短动画；减少动态效果时移除非必要位移动画；随系统主题变化，安全区域与键盘由系统布局管理。
- [ ] 备忘失焦、scenePhase inactive/background、回到 active 及显著时间变化通知调用 flush/refreshCalendar；后台保存使用有限系统后台执行窗口并正确结束，不承诺强制杀进程仍能完成未写入数据。
- [ ] 检查导入的安全作用域文件访问，结束后释放访问；取消文件选择不报错误；原生导出可以被旧网页导入。
- [ ] 将现有图标图形制作成合规 AppIcon（不使用 AI 编辑）；运行 UI 测试，保存浅色/深色/大字体截图并人工检查；提交 `feat: build native planner interface and backup tools`。

### Task 5: 云端测试、可安装产物与性能基准

**Files:** `scripts/ci-test.sh`、`scripts/build-ipa.sh`、`.github/workflows/ios-native.yml`、`AppTests/PlannerViewModelTests.swift`、`.gitignore`。

**Interfaces:**
- `ci-test.sh` 从工程目录运行，验证 Xcode 版本、执行 swift test、生成 Xcode 工程，再用可用的 iPhone 17 Pro / iOS 26.5 模拟器执行 `xcodebuild test -project Planner.xcodeproj -scheme Planner -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath build/Tests.xcresult CODE_SIGNING_ALLOWED=NO`。
- `build-ipa.sh` 执行 Release generic iOS 真机编译，使用 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`，产物归档到 `build/Planner-unsigned.ipa`，只包含当前构建的 Payload/Planner.app。
- Workflow：push 指定 native/workflow 路径、pull_request、workflow_dispatch；permissions contents:read；分支级 concurrency 取消旧构建；timeout 30 分钟；产物保留 7 天。

- [ ] 固定 XcodeGen 2.46.0，从官方 tag 获取并校验固定提交后编译生成工具；不调用浮动 Homebrew 最新版本。具体 tag SHA 从官方 Git 远端解析、记录并固定到脚本。
- [ ] 在标准 macos-26 上输出 xcodebuild -version 和 swift --version，路径缺失立即失败；安装运行器当前含有的固定模拟器，不下载任意 preview SDK。
- [ ] 完成 core、store、App 和 UI 测试；测试失败则不发布 IPA。上传 xcresult 和界面截图辅助定位失败，不把失败吞成成功。
- [ ] 构造规范和压力数据 fixture，测试 snapshot 不改变源文档、快速完成准确保存；记录测量时间作为基线，不用模拟器结果断言真机帧率。
- [ ] 构建 IPA 后通过 unzip/plutil 检查 Payload、可执行文件、Bundle ID、MinimumOSVersion、版本和 arm64 架构；macOS 运行日志和 IPA SHA256 一同输出。
- [ ] 在 GitHub 实际跑一次完整 workflow，取得成功运行链接与可下载 IPA；失败按根因修复直到通过。只有已验证的运行才写入交付记录。
- [ ] 回归 `node --test tests/planner.test.cjs` 确认 5 项网页测试通过；提交 `ci: build and verify native iOS IPA on GitHub`。

### Task 6: 安装、旧数据迁移与自动续签验收

**Files:** `native/Planner/README.md`、`docs/ios-install.md`、`docs/ios-acceptance.md`、根 `README.md`。

**Interfaces:** 交付可下载的确切 workflow run/artifact 链接，用户手机操作步骤与验收表；不依赖用户拥有 Mac。

- [ ] 编写中文路径：网页版导出 JSON → Windows 通过 SideStore 当前官方流程完成首次安装 → 个人 Apple 登录和设备信任 → 导入已生成的 IPA → 原生计划本导入旧备份。密码与验证码由用户在相应设备/官方工具内输入。
- [ ] 明确保留网页数据，原生确认迁移完成之前不清理；备份存到应用沙盒之外。说明“刷新签名”和“安装新版 IPA”是两个动作。
- [ ] 提供当前官方 SideStore/LocalDevVPN 入口与配对步骤，按实际安装版本核实快捷指令 action 名称，不能凭空编写一个不存在的自动化。
- [ ] 用户设备上先手动续签，记录有效期延长且计划数据不变；再配置每日自动刷新，验证 Wi-Fi、本地 VPN、锁屏条件和实际触发结果，失败按官方错误信息修复。
- [ ] 真机验收表记录：iPhone 14 Pro/iOS 27.0、App 构建号、首次安装、数据数量、离线操作、重开保存、导出、手动续签、自动触发。没有观察到的结果写“未验证”，不预填成功。
- [ ] Release 真机体验检查连续滚动、勾选、切换日期和输入；若有可用 Instruments，检查重复出现的 >100ms 主线程工作；否则保留“未测帧率”说明及用户体验结论。
- [ ] 完成全分支审查并修复实际问题；发现新变更时重跑相关测试。需要 PR 时创建并附加到当前聊天；不自行合并。交付明确区分代码/云端已完成与手机待用户完成步骤。
- [ ] 提交 `docs: add native iOS installation and renewal guide`。

## 计划自查

- 已覆盖设计中的原有功能、迁移、原子存储、局部撤销、原生控件、辅助功能、性能、构建、安装与续签。
- generation/revision 与主线程 UI 协调分工一致；导入旧任务 ID 不依赖 UUID。
- 云端 iOS 26.5 模拟器与用户 iOS 27.0 真机分别记录，避免把构建环境版本当成用户设备版本。
- 缺少 Mac 不阻止在 Windows 写代码，但实际原生测试由 GitHub Actions 执行；当前尚未创建该工作流或运行原生测试。
- 推荐本会话直接执行：六项任务对同一数据格式和状态接口依赖紧密，单一实现者易保持一致；完成后独立审查整个分支。

## 执行方式审阅

用户已批准设计；本计划待用户审阅和选择执行方式。两种方式：本会话直接执行（推荐，成本较低），或按任务使用子代理并逐项独立审查（上下文与审查成本更高）。

## 核实来源

- macOS 镜像与 Xcode/模拟器：https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md
- XcodeGen 固定版本：https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0
- 其余平台及签名约束参见已批准设计的依据章节。
