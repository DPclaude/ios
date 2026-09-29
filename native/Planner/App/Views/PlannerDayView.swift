import SwiftUI
import PlannerCore

private enum PlannerSheet: Identifiable {
    case add(UUID), settings, date, edit(TaskItem)
    var id: String {
        switch self {
        case .add(let request): return "add-\(request)"
        case .settings: return "settings"
        case .date: return "date"
        case .edit(let item): return "edit-\(item.id)"
        }
    }
}

struct PlannerDayView: View {
    let model: PlannerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeSheet: PlannerSheet?
    @State private var sorting = false
    @State private var completedExpanded = true
    @State private var feedback = 0
    @State private var deletingRepeat: TaskItem?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    dateHeader
                    WeekStrip(day: model.selectedDay) { model.select(day: $0) }
                    progress
                }.listRowSeparator(.hidden)
                Section { categories }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if let error = model.loadError {
                    Section("数据暂时无法读取") {
                        Text(error).foregroundStyle(.red)
                        Text("原文件已保留。请重试，或在设置中恢复导入前的副本。")
                        Button("重新读取") { Task { await model.load() } }
                    }
                } else if !model.isLoaded {
                    ProgressView("正在读取计划")
                } else {
                    Section("待完成 · \(model.snapshot.open.count)") {
                        if model.snapshot.open.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("给今天留一点从容", systemImage: "sun.max") .font(.headline)
                                Text(model.snapshot.totalCount == 0 ? "从一件小事开始，写下你的计划。" : "这个分类下没有待办计划。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 16)
                        }
                        ForEach(model.snapshot.open) { row($0) }
                            .onMove { model.movePlans(from: $0, to: $1, completed: false) }
                    }
                    if !model.snapshot.completed.isEmpty {
                        Section {
                            DisclosureGroup("已完成 · \(model.snapshot.completed.count)", isExpanded: $completedExpanded) {
                                ForEach(model.snapshot.completed) { row($0) }
                                    .onMove { model.movePlans(from: $0, to: $1, completed: true) }
                            }
                        }
                    }
                    Section("当天备忘") { DailyNoteView(model: model, day: model.selectedDay).id(model.selectedDay) }
                    Section { saveStatus }.listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped).scrollDismissesKeyboard(.interactively)
            .environment(\.editMode, .constant(sorting ? .active : .inactive))
            .navigationTitle("计划本")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("今天") { model.select(day: .today()); Task { await model.refreshCalendar() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button(sorting ? "完成排序" : "排序") { withAnimation { sorting.toggle() } }
                            .accessibilityIdentifier("reorderPlans").disabled(!model.canEdit)
                        Button { model.openSlice() } label: { Image(systemName: "scribble.variable") }
                            .accessibilityLabel("全屏划掉今天的计划").accessibilityIdentifier("openSlice").disabled(!model.canEdit)
                        Button { activeSheet = .settings } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("设置").accessibilityIdentifier("settings")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings: SettingsView(model: model)
                case .add: TaskEditor(model: model, item: nil)
                case .edit(let item): TaskEditor(model: model, item: item)
                case .date: datePicker
                }
            }
            .onChange(of: model.isShowingAdd, initial: true) { _, requested in
                if requested {
                    if model.isShowingSlice { model.isShowingSlice = false }
                    else { presentRequestedAdd() }
                }
            }
            .fullScreenCover(isPresented: Binding(get: { model.isShowingSlice }, set: { model.isShowingSlice = $0 }), onDismiss: presentRequestedAdd) {
                SliceCompletionView(model: model)
            }
            .confirmationDialog("删除整条每日计划？", isPresented: Binding(get: { deletingRepeat != nil }, set: { if !$0 { deletingRepeat = nil } }), titleVisibility: .visible) {
                Button("删除整条重复规则", role: .destructive) {
                    if let item = deletingRepeat { act(.delete(item.reference)) }; deletingRepeat = nil
                }
            } message: { Text("这会移除所有日期的该规则及其完成记录，可在 7 秒内撤销。") }
            .sensoryFeedback(.success, trigger: feedback)
        }
    }
    private var dateHeader: some View {
        HStack {
            Button { model.select(day: model.selectedDay.adding(days: -1)) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("前一天")
            Spacer(minLength: 0)
            Button { activeSheet = .date } label: {
                Text(model.selectedDay.date(), format: .dateTime.year().month().day()).font(.headline)
            }.accessibilityLabel("选择日期")
            Spacer(minLength: 0)
            Button { model.select(day: model.selectedDay.adding(days: 1)) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("后一天")
        }.buttonStyle(.plain)
    }
    private var progress: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.orange.opacity(0.15), lineWidth: 6)
                Circle().trim(from: 0, to: model.snapshot.totalCount == 0 ? 0 : Double(model.snapshot.completedCount) / Double(model.snapshot.totalCount))
                    .stroke(.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: "checkmark").font(.headline).foregroundStyle(.orange)
            }.frame(width: 44, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("每一步，都算数").font(.headline)
                Text("已完成 \(model.snapshot.completedCount) / \(model.snapshot.totalCount) 项").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
    private var categories: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                categoryButton("全部", value: nil)
                ForEach(1..<4) { categoryButton(PlannerCategory.names[$0], value: $0) }
            }.padding(.vertical, 5)
        }.scrollIndicators(.hidden)
    }
    private func categoryButton(_ name: String, value: Int?) -> some View {
        Button(name) { model.select(category: value) }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
            .foregroundStyle(model.category == value ? Color.white : .primary)
            .background(model.category == value ? Color.orange : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .accessibilityAddTraits(model.category == value ? .isSelected : [])
    }
    private func act(_ action: PlannerAction) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { model.perform(action) }
        feedback += 1
    }
    private func row(_ item: TaskItem) -> some View {
        TaskRow(item: item, toggle: { act(.toggle(item.reference)) }, edit: { if !sorting { activeSheet = .edit(item) } })
            .disabled(!model.canEdit)
            .swipeActions(edge: .trailing, allowsFullSwipe: !item.reference.isRepeating) {
                Button(role: .destructive) {
                    if item.reference.isRepeating { deletingRepeat = item } else { act(.delete(item.reference)) }
                } label: { Label("删除", systemImage: "trash") }
            }
            .swipeActions(edge: .leading) {
                if case .task(let id) = item.reference {
                    Button { act(.tomorrow(id)) } label: { Label("明天", systemImage: "arrow.right") }.tint(.blue)
                    Button { act(.pin(id)) } label: { Label("置顶", systemImage: "pin") }.tint(.orange)
                }
            }
    }
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if model.undoAvailable {
                HStack {
                    Text("已删除计划").font(.subheadline)
                    Spacer()
                    Button("撤销") { model.undoDelete() }.bold().accessibilityIdentifier("undoDelete")
                }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            Button { activeSheet = .add(UUID()) } label: { Label("添加计划", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .accessibilityIdentifier("addTask").disabled(!model.canEdit)
        }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }
    private func presentRequestedAdd() {
        guard model.isShowingAdd else { return }
        activeSheet = .add(UUID())
        model.isShowingAdd = false
    }
    @ViewBuilder private var saveStatus: some View {
        switch model.saveState {
        case .saved: Label("所有更改已保存", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("saveComplete")
        case .saving: Label("正在保存…", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("尚未保存", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Text(message).font(.caption)
                Button("重试保存") { Task { await model.retrySave() } }
                Text("内容仍在内存中，也可以到设置导出备份。").font(.caption)
            }
        }
    }
    private var datePicker: some View {
        NavigationStack {
            DatePicker("选择日期", selection: Binding(get: { model.selectedDay.date() }, set: { model.select(day: .today(now: $0)) }), displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
                .navigationTitle("选择日期").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { activeSheet = nil } } }
        }.presentationDetents([.medium, .large])
    }
}
