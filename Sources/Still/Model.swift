import Foundation
import Observation

@MainActor @Observable final class TimerStore {
    private(set) var tasks: [Countdown] = []
    var palette: Palette = .original { didSet { if palette != oldValue { save() } } }
    // Preview-only setting; tasks own their reminder levels.
    var previewLevel = "轻提醒" { didSet { if previewLevel != oldValue { save() } } }
    private(set) var menuTaskID: UUID?
    var appearanceMode: AppearanceMode = .auto { didSet { if appearanceMode != oldValue { save() } } }
    var capsulePosition = CapsulePosition() { didSet { if capsulePosition != oldValue { save() } } }
    var settingsPresented = false
    private(set) var storageError: String?
    @ObservationIgnored var onCompletion: (([Countdown], Bool) -> Void)?
    @ObservationIgnored var previewReminder: (() -> Void)?
    @ObservationIgnored private var loading = true
    @ObservationIgnored private var writable = true
    @ObservationIgnored private var needsLegacyBackup = false
    @ObservationIgnored private var lastRunSequence = 0
    @ObservationIgnored private var recoveryCompletions: [UUID: Countdown] = [:]
    @ObservationIgnored private let storage: StateFileStorage
    @ObservationIgnored let clock: () -> Date

    init(file: URL? = nil, clock: @escaping () -> Date = Date.init,
         writer: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.clock = clock
        let file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Still/state.json")
        storage = StateFileStorage(file: file, writeData: writer)
        do {
            if let state = try storage.load() {
                needsLegacyBackup = state.version == 1
                var restored = state.tasks
                lastRunSequence = restored.compactMap(\.runSequence).max() ?? 0
                for i in restored.indices {
                    if restored[i].reminderLevel == nil {
                        restored[i].reminderLevel = state.version == 1 ? (ReminderLevel(rawValue: state.reminder) ?? .light) : .light
                    }
                    if restored[i].deadline != nil && restored[i].runSequence == nil {
                        restored[i].runSequence = allocateRunSequence()
                    }
                }
                tasks = restored
                palette = state.palette
                menuTaskID = state.menuTaskID
                appearanceMode = state.appearanceMode ?? .auto
                capsulePosition = state.capsulePosition ?? CapsulePosition()
                previewLevel = ReminderLevel(rawValue: state.reminder)?.rawValue ?? ReminderLevel.light.rawValue
            }
        } catch {
            writable = false
            storageError = "无法读取保存数据，原文件已保留。请检查：" + file.path
        }
        menuTaskID = selection(for: tasks, at: clock())
        loading = false
    }

    var menuTask: Countdown? {
        let now = clock()
        return tasks.first { $0.id == menuTaskID && $0.deadline != nil && $0.remaining(at: now) > 0 }
    }

    private func selection(for tasks: [Countdown], at now: Date) -> UUID? {
        let running = tasks.filter { $0.deadline != nil && $0.remaining(at: now) > 0 }
        if running.contains(where: { $0.id == menuTaskID }) { return menuTaskID }
        return running.min { ($0.runSequence ?? 0) < ($1.runSequence ?? 0) }?.id
    }

    private func allocateRunSequence() -> Int? {
        guard lastRunSequence < Countdown.maximumRunSequence else {
            storageError = "计时序号已耗尽，无法启动新的计时。"
            return nil
        }
        lastRunSequence += 1
        return lastRunSequence
    }

    private func commitTasks(_ updated: [Countdown]) {
        guard updated != tasks else { return }
        let selected = selection(for: updated, at: clock())
        tasks = updated
        menuTaskID = selected
        save()
    }

    func selectMenuTask(_ id: UUID) {
        guard menuTaskID != id, tasks.contains(where: { $0.id == id && $0.deadline != nil && $0.remaining(at: clock()) > 0 }) else { return }
        menuTaskID = id
        save()
    }

    func cycleReminder(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        var updated = tasks
        updated[i].reminderLevel = updated[i].intensity.next
        commitTasks(updated)
    }

    func move(_ id: UUID, relativeTo target: UUID, after: Bool) {
        guard id != target, let task = tasks.first(where: { $0.id == id }), tasks.contains(where: { $0.id == target }) else { return }
        var reordered = tasks.filter { $0.id != id }
        guard let index = reordered.firstIndex(where: { $0.id == target }) else { return }
        reordered.insert(task, at: index + (after ? 1 : 0))
        commitTasks(reordered)
    }

    func moveByKeyboard(_ id: UUID, down: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + (down ? 1 : -1)
        guard tasks.indices.contains(j) else { return }
        move(id, relativeTo: tasks[j].id, after: down)
    }

    @discardableResult func save() -> Bool {
        persist(tasks: tasks, menuTaskID: menuTaskID)
    }

    private func persist(tasks: [Countdown], menuTaskID: UUID?) -> Bool {
        guard !loading, writable else { return false }
        do {
            try storage.save(SavedState(tasks: tasks, palette: palette, reminder: previewLevel, menuTaskID: menuTaskID,
                                        appearanceMode: appearanceMode, capsulePosition: capsulePosition),
                             preservingLegacyFile: needsLegacyBackup)
            needsLegacyBackup = false
            storageError = nil
            return true
        } catch {
            storageError = "保存失败：" + error.localizedDescription
            return false
        }
    }

    func reconcile(recovery: Bool = false) {
        let now = clock()
        let completed = tasks.filter { $0.deadline != nil && $0.remaining(at: now) == 0 }
        // A user can reset/restart while saving fails: retain only the same runs.
        recoveryCompletions = recoveryCompletions.filter { id, task in
            completed.contains { $0.id == id && $0.runSequence == task.runSequence }
        }
        if recovery { for task in completed { recoveryCompletions[task.id] = task } }
        guard !completed.isEmpty else { return }
        let ids = Set(completed.map(\.id))
        var updated = tasks
        for i in updated.indices where ids.contains(updated[i].id) {
            updated[i].deadline = nil
            updated[i].frozen = 0
        }
        let selected = selection(for: updated, at: now)
        // Keep expired deadlines on failure, so a later tick retries the commit.
        guard persist(tasks: updated, menuTaskID: selected) else {
            // Presentation must still hand off to a live timer while the
            // completed task remains pending for a durable retry.
            menuTaskID = selected
            return
        }
        tasks = updated
        menuTaskID = selected
        let recovered = completed.filter { recoveryCompletions[$0.id] != nil }
        let regular = completed.filter { recoveryCompletions[$0.id] == nil }
        recoveryCompletions.removeAll()
        if !recovered.isEmpty { onCompletion?(recovered, true) }
        if !regular.isEmpty { onCompletion?(regular, false) }
    }

    func toggle(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let now = clock()
        var task = tasks[i]
        let remaining = task.remaining(at: now)
        if remaining == 0 {
            task.duration = task.originalDuration ?? task.duration
            task.originalDuration = nil
            task.frozen = task.duration
            task.deadline = now.addingTimeInterval(task.duration)
        } else if task.deadline != nil {
            task.frozen = remaining
            task.deadline = nil
        } else {
            task.deadline = now.addingTimeInterval(remaining)
        }
        if task.deadline != nil {
            guard let sequence = allocateRunSequence() else { return }
            task.runSequence = sequence
        }
        var updated = tasks
        updated[i] = task
        commitTasks(updated)
    }

    func reset(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        var updated = tasks
        updated[i].duration = updated[i].originalDuration ?? updated[i].duration
        updated[i].originalDuration = nil
        updated[i].deadline = nil
        updated[i].frozen = updated[i].duration
        commitTasks(updated)
    }

    func snooze(completions: [Countdown]) {
        var updated = tasks
        let now = clock()
        for i in updated.indices where updated[i].deadline == nil && updated[i].frozen == 0 {
            guard completions.contains(where: { $0.id == updated[i].id && $0.runSequence == updated[i].runSequence }),
                  let sequence = allocateRunSequence() else { continue }
            updated[i].originalDuration = updated[i].originalDuration ?? updated[i].duration
            updated[i].duration = 300
            updated[i].frozen = 300
            updated[i].deadline = now.addingTimeInterval(300)
            updated[i].runSequence = sequence
        }
        commitTasks(updated)
    }

    func remove(_ id: UUID) { commitTasks(tasks.filter { $0.id != id }) }

    func color(_ id: UUID, _ slot: Int) {
        guard (0..<5).contains(slot), let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        var updated = tasks
        updated[i].slot = slot
        commitTasks(updated)
    }

    func nextColorSlot() -> Int {
        var counts = Array(repeating: 0, count: 5)
        for task in tasks { counts[task.slot] += 1 }
        let minimum = counts.min() ?? 0
        let choices = counts.indices.filter { counts[$0] == minimum }
        return choices.first { $0 != tasks.last?.slot } ?? choices.first ?? 0
    }

    func add(_ name: String, minutes: Double, startImmediately: Bool = false) {
        guard minutes.isFinite, minutes >= 1.0 / 60, minutes <= 1440 else { return }
        let sequence = startImmediately ? allocateRunSequence() : nil
        guard !startImmediately || sequence != nil else { return }
        let duration = minutes * 60
        let task = Countdown(name: name.isEmpty ? "新的倒计时" : String(name.prefix(40)), duration: duration,
                             deadline: startImmediately ? clock().addingTimeInterval(duration) : nil,
                             frozen: duration, slot: nextColorSlot(), reminderLevel: .light, runSequence: sequence)
        commitTasks(tasks + [task])
    }
}
