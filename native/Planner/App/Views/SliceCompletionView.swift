import SwiftUI
import PlannerCore

struct SliceCompletionView: View {
    let model: PlannerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var visible: [TaskItem] = []
    @State private var animating: TaskReference?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.selectedDay.date(), format: .dateTime.month().day().weekday()).font(.subheadline).foregroundStyle(.secondary)
                        Text("把今天，\n一件件划掉。").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        HStack {
                            Text("已完成 \(model.snapshot.completedCount) / \(model.snapshot.totalCount)")
                            Spacer()
                            Image(systemName: "sparkles").foregroundStyle(.orange)
                        }.font(.subheadline)
                        ProgressView(value: Double(model.snapshot.completedCount), total: Double(max(1, model.snapshot.totalCount))).tint(.orange)
                    }.padding(.bottom, 4)
                    if !model.canEdit {
                        Text(model.loadError ?? "正在读取计划…").foregroundStyle(.secondary)
                    } else if visible.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.orange)
                            Text(model.snapshot.totalCount == 0 ? "今天还没有计划" : "今天的计划已完成").font(.title2.bold())
                            Text("给自己一点休息的时间。").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 50)
                    } else {
                        Text("横向划过卡片，完成一件事").font(.caption).foregroundStyle(.secondary)
                        LazyVStack(spacing: 16) {
                            ForEach(visible) { item in
                                SliceCard(item: item, cut: {
                                    guard animating == nil, model.canEdit else { return false }
                                    animating = item.reference
                                    guard model.completeForSlice(item.reference) else { animating = nil; return false }
                                    return true
                                }, finished: {
                                    animating = nil; visible = model.snapshot.open
                                })
                                .disabled(animating != nil || !model.canEdit)
                            }
                        }
                    }
                    saveStatus
                }.padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("划掉计划").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("closeSlice")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.sliceUndoAvailable {
                    Button { model.undoSliceCompletion(); visible = model.snapshot.open } label: {
                        Label("撤销上一次完成", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .accessibilityIdentifier("undoSlice").disabled(animating != nil || !model.canEdit)
                        .padding().background(.bar)
                }
            }
            .onAppear { visible = model.snapshot.open }
            .onChange(of: model.snapshot.open) { _, items in if animating == nil { visible = items } }
        }.tint(.orange)
    }
    @ViewBuilder private var saveStatus: some View {
        switch model.saveState {
        case .saved: Text("已保存").font(.caption).foregroundStyle(.secondary)
        case .saving: ProgressView("正在保存…").font(.caption)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("尚未保存", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Text(message).font(.caption)
                Button("重试保存") { Task { await model.retrySave() } }
            }
        }
    }
}

private struct SliceCard: View {
    let item: TaskItem
    let cut: () -> Bool
    let finished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trail: [CGPoint] = []
    @State private var peakVertical: CGFloat = 0
    @State private var slicing = false
    @State private var progress: CGFloat = 0
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if slicing && !reduceMotion {
                    cardContent.mask(SliceHalf(top: true))
                        .offset(x: -32 * progress, y: -22 * progress)
                        .rotationEffect(.degrees(-Double(progress) * 9)).opacity(1 - progress)
                    cardContent.mask(SliceHalf(top: false))
                        .offset(x: 38 * progress, y: 38 * progress)
                        .rotationEffect(.degrees(Double(progress) * 12)).opacity(1 - progress)
                    ForEach(0..<14, id: \.self) { index in
                        let angle = Double(index) * .pi * 2 / 14
                        Capsule().fill(index.isMultiple(of: 3) ? Color.yellow : Color.orange)
                            .frame(width: 4, height: CGFloat(8 + index % 4 * 3))
                            .rotationEffect(.radians(angle + Double(progress)))
                            .offset(x: CGFloat(cos(angle)) * progress * 110, y: CGFloat(sin(angle)) * progress * 85)
                            .opacity(Double(1 - progress)).accessibilityHidden(true)
                    }
                } else {
                    cardContent.opacity(1 - progress)
                }
                blade.stroke(.orange.opacity(0.3), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .blur(radius: 4).opacity(1 - progress)
                blade.stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .shadow(color: .orange.opacity(0.7), radius: 6).opacity(1 - progress)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 18)
                .onChanged { value in
                    guard !slicing else { return }
                    peakVertical = max(peakVertical, abs(value.translation.height))
                    if abs(value.translation.width) > peakVertical * 2.2 {
                        if trail.isEmpty { trail.append(value.startLocation) }
                        trail.append(value.location)
                        if trail.count > 18 { trail.removeFirst() }
                    } else { trail = [] }
                }
                .onEnded { value in
                    defer { peakVertical = 0 }
                    if SliceRules.accepts(horizontal: Double(value.translation.width), vertical: Double(peakVertical), width: Double(geometry.size.width)) { begin() }
                    else { trail = [] }
                })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("slice-\(item.text)")
            .accessibilityAction(named: "完成计划") { begin() }
        }
        .frame(height: 142)
        .sensoryFeedback(.success, trigger: slicing)
        .task(id: slicing) {
            guard slicing else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.18 : 0.55)) { progress = 1 }
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 220 : 600)) } catch { return }
            finished()
        }
    }
    private func begin() {
        guard !slicing, cut() else { return }
        slicing = true
        // Completion is already recorded and queued for persistence; animation only controls the visual.
    }
    private var blade: Path {
        Path { path in
            guard let first = trail.first else { return }
            path.move(to: first)
            for point in trail.dropFirst() { path.addLine(to: point) }
        }
    }
    private var cardContent: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.text).font(.title3.weight(.semibold)).lineLimit(3).minimumScaleFactor(0.85)
                HStack {
                    Text(PlannerCategory.names[item.cat])
                    if item.reference.isRepeating { Image(systemName: "repeat") }
                    Spacer()
                    Image(systemName: "arrow.left.and.right")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Button { begin() } label: {
                Image(systemName: "checkmark").font(.headline).frame(width: 44, height: 44)
                    .background(Color.orange.opacity(0.13), in: Circle())
            }.buttonStyle(.plain).foregroundStyle(.orange).accessibilityLabel("完成：\(item.text)")
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.orange.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
        .accessibilityHidden(slicing)
    }
}

private struct SliceHalf: Shape {
    let top: Bool
    func path(in rect: CGRect) -> Path {
        let left = rect.height * 0.58, right = rect.height * 0.42
        return Path { path in
            if top {
                path.move(to: .zero); path.addLine(to: CGPoint(x: rect.width, y: 0))
                path.addLine(to: CGPoint(x: rect.width, y: right)); path.addLine(to: CGPoint(x: 0, y: left))
            } else {
                path.move(to: CGPoint(x: 0, y: left)); path.addLine(to: CGPoint(x: rect.width, y: right))
                path.addLine(to: CGPoint(x: rect.width, y: rect.height)); path.addLine(to: CGPoint(x: 0, y: rect.height))
            }
            path.closeSubpath()
        }
    }
}
