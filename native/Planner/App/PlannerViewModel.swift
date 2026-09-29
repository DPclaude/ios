import Foundation
import Observation
import PlannerCore
import PlannerStore

enum SaveState: Equatable { case saved, saving, failed(String) }
enum PlannerAction {
    case add(text: String, category: Int, day: Day, repeating: Bool)
    case toggle(TaskReference)
    case edit(TaskReference, text: String, category: Int)
    case reschedule(taskID: String, day: Day)
    case pin(String), tomorrow(String), makeDaily(String)
    case cancelDaily(ruleID: String, day: Day)
    case delete(TaskReference)
}
struct ImportPreview: Identifiable, Sendable {
    let id = UUID()
    let document: PlannerDocument
}

@MainActor @Observable final class PlannerViewModel {
    private(set) var document = PlannerDocument()
    private(set) var selectedDay: Day
    private(set) var category: Int?
    private(set) var snapshot = DaySnapshot()
    private(set) var saveState: SaveState = .saved
    private(set) var loadError: String?
    private(set) var isLoaded = false
    private(set) var isBusy = false
    private(set) var undoAvailable = false
    var canEdit: Bool { isLoaded && loadError == nil && !isBusy }
    @ObservationIgnored private let store: PlannerFileStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var queuedRevision: UInt64 = 0
    @ObservationIgnored private var previousToday: Day
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var noteTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var removed: RemovedItem?
    @ObservationIgnored private var undoDeadline = Date.distantPast

    init(store: PlannerFileStore, now: @escaping () -> Date = { Date() }, timeZone: @escaping () -> TimeZone = { .current }) {
        self.store = store; self.now = now; self.timeZone = timeZone
        let today = Day.today(now: now(), timeZone: timeZone())
        selectedDay = today; previousToday = today
    }
    func load() async {
        guard !isLoaded else { return }
        do {
            apply(try await store.load()); isLoaded = true; loadError = nil
            await refreshCalendar()
        } catch { loadError = error.localizedDescription }
    }
    private func apply(_ value: StoreSnapshot) {
        document = value.document; generation = value.generation; revision = value.revision
        queuedRevision = revision; saveState = .saved; rebuild()
    }
    private func rebuild() { snapshot = document.snapshot(day: selectedDay, category: category) }
    func select(day: Day) {
        noteTask?.cancel(); enqueueSave()
        selectedDay = day; rebuild()
    }
    func select(category: Int?) { self.category = category; rebuild() }
    func perform(_ action: PlannerAction) {
        guard canEdit else { return }
        switch action {
        case .add(let text, let cat, let day, let daily):
            let id = UUID().uuidString
            document.add(text: text, category: cat, day: day, id: id)
            if daily { document.convertToRepeat(taskID: id, ruleID: UUID().uuidString) }
        case .toggle(let ref): document.toggle(ref, now: now())
        case .edit(let ref, let text, let cat): document.edit(ref, text: text, category: cat)
        case .reschedule(let id, let day):
            if let i = document.tasks.firstIndex(where: { $0.id == id }) { document.tasks[i].date = day.rawValue; document.tasks[i].rolled = false }
        case .pin(let id): document.pin(taskID: id)
        case .tomorrow(let id): document.moveToNextDay(taskID: id, timeZone: timeZone())
        case .makeDaily(let id): document.convertToRepeat(taskID: id, ruleID: UUID().uuidString)
        case .cancelDaily(let id, let day): document.cancelRepeat(ruleID: id, day: day, taskID: UUID().uuidString, now: now())
        case .delete(let ref):
            guard let item = document.remove(ref) else { return }
            removed = item; undoDeadline = now().addingTimeInterval(7); undoAvailable = true
            undoTask?.cancel()
            undoTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(7)) } catch { return }
                self?.clearUndo()
            }
        }
        changed(); enqueueSave()
    }
    private func changed() { revision += 1; saveState = .saving; rebuild() }
    func updateNote(_ text: String, for day: Day) {
        guard canEdit, document.notes[day.rawValue, default: ""] != text else { return }
        document.notes[day.rawValue] = text; revision += 1; saveState = .saving
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.enqueueSave()
        }
    }
    private func enqueueSave(force: Bool = false) {
        guard isLoaded, loadError == nil, force || revision > queuedRevision else { return }
        let pending = StoreSnapshot(document: document, generation: generation, revision: revision)
        queuedRevision = revision; saveState = .saving
        let previous = saveTask, fileStore = store
        saveTask = Task { [weak self] in
            await previous?.value
            do {
                try await fileStore.save(pending)
                if let self, self.generation == pending.generation, self.revision == pending.revision { self.saveState = .saved }
            } catch {
                if let self, self.generation == pending.generation, self.revision == pending.revision { self.saveState = .failed(error.localizedDescription) }
            }
        }
    }
    func flush() async {
        noteTask?.cancel(); noteTask = nil
        enqueueSave()
        await saveTask?.value
    }
    func retrySave() async { enqueueSave(force: true); await saveTask?.value }
    func refreshCalendar() async {
        guard canEdit else { return }
        let today = Day.today(now: now(), timeZone: timeZone())
        if selectedDay == previousToday { selectedDay = today }
        previousToday = today
        let original = document
        document.rollover(today: today, timeZone: timeZone())
        if original != document { changed(); enqueueSave() } else { rebuild() }
    }
    func undoDelete(now: Date) {
        guard canEdit, undoAvailable, now <= undoDeadline, let removed else { clearUndo(); return }
        document.restore(removed, today: Day.today(now: self.now(), timeZone: timeZone()), timeZone: timeZone())
        clearUndo(); changed(); enqueueSave()
    }
    private func clearUndo() { undoTask?.cancel(); undoAvailable = false; removed = nil }
    func prepareImport(data: Data) async throws -> ImportPreview {
        ImportPreview(document: try await store.decodeBackup(data))
    }
    func prepareImport(url: URL) async throws -> ImportPreview {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return ImportPreview(document: try await store.readBackup(url: url))
    }
    func confirmImport(_ preview: ImportPreview) async throws {
        guard canEdit else { throw BackupError.invalid("当前保存状态") }
        isBusy = true; defer { isBusy = false }
        await flush()
        if case .failed(let message) = saveState { throw BackupError.invalid("当前保存状态：\(message)") }
        let next = try await store.replace(with: preview.document)
        clearUndo(); apply(next)
        isBusy = false; await refreshCalendar()
    }
    func exportData() async throws -> Data { try await store.encodeBackup(document) }
    func recoverPreviousImport() async throws {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        await flush()
        let restored = try await store.recoverPreviousImport()
        clearUndo(); apply(restored); isLoaded = true; loadError = nil
        isBusy = false; await refreshCalendar()
    }
}
