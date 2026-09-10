import SwiftUI
enum ReminderLevel: String, Codable, CaseIterable {
    case light = "轻提醒", medium = "醒目提醒", strong = "强打断"
    var next: Self { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
}
struct Countdown: Identifiable, Codable {
    var id = UUID()
    var name: String
    var duration: TimeInterval
    var deadline: Date?
    var frozen: TimeInterval
    var slot: Int
    var reminderLevel: ReminderLevel?
    var runSequence: Int?
    var intensity: ReminderLevel { reminderLevel ?? .light }
    func remaining(at now: Date) -> TimeInterval { max(0, deadline.map { $0.timeIntervalSince(now) } ?? frozen) }
    func progress(at now: Date) -> Double { min(1, max(0, 1 - remaining(at: now) / duration)) }
}
enum Palette: String, CaseIterable, Codable {
    case original = "原样", apple = "苹果灵感 II", google = "谷歌灵感 II"
    var hex: [UInt32] {
        switch self {
        case .original: [0x25877f,0x8765bd,0x327db4,0xb26079,0x8b782a]
        case .apple: [0x5856d6,0xce325f,0x007d9c,0x7841b3,0x29884b]
        case .google: [0x6750a4,0xa44436,0x157565,0x87651f,0x3866a0]
        }
    }
    func color(_ slot: Int) -> Color { let h = hex[slot % 5]; return Color(red: Double((h >> 16) & 255)/255, green: Double((h >> 8) & 255)/255, blue: Double(h & 255)/255) }
}
enum AppearanceMode: String, Codable, CaseIterable {
    case light, dark, auto
    var title: String { switch self { case .light: "白天"; case .dark: "黑夜"; case .auto: "自动" } }
    var icon: String { switch self { case .light: "sun.max"; case .dark: "moon"; case .auto: "circle.lefthalf.filled" } }
    var appearance: NSAppearance? {
        switch self { case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua); case .auto: nil }
    }
}
struct CapsulePosition: Codable, Equatable {
    enum Edge: String, Codable { case left, right }
    var edge: Edge = .right
    var top: Double = 24
    func frame(in screen: CGRect, size: CGSize) -> CGRect {
        let inset: CGFloat = 12
        let x = edge == .right ? screen.maxX - size.width - inset : screen.minX + inset
        let offset = min(max(inset, top.isFinite ? top : 24), max(inset, screen.height - size.height - inset))
        return CGRect(x: x, y: screen.maxY - offset - size.height, width: size.width, height: size.height)
    }
}
struct SavedState: Codable {
    var version = 2
    var tasks: [Countdown]
    var palette: Palette
    var reminder: String
    var menuTaskID: UUID?
    var appearanceMode: AppearanceMode?
    var capsulePosition: CapsulePosition?
}
@MainActor @Observable final class TimerStore {
    var tasks: [Countdown] = [] { didSet { updateMenuSelection(); save() } }
    var palette: Palette = .original { didSet { save() } }
    // Preview-only setting; tasks own their reminder levels.
    var previewLevel = "轻提醒" { didSet { save() } }
    var menuTaskID: UUID? { didSet { save() } }
    var appearanceMode: AppearanceMode = .auto { didSet { save() } }
    var capsulePosition = CapsulePosition() { didSet { save() } }
    var settingsPresented = false
    var storageError: String?
    @ObservationIgnored var onCompletion: (([Countdown], Bool) -> Void)?
    @ObservationIgnored var previewReminder: (() -> Void)?
    @ObservationIgnored private var loading = true
    @ObservationIgnored private var writable = true
    @ObservationIgnored private var needsLegacyBackup = false
    @ObservationIgnored let file: URL
    @ObservationIgnored let clock: () -> Date
    init(file: URL? = nil, clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Still/state.json")
        if FileManager.default.fileExists(atPath: self.file.path) {
            do {
                let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: self.file))
                guard (1...2).contains(state.version), state.tasks.allSatisfy({ $0.duration.isFinite && $0.duration > 0 && $0.duration <= 86400 && $0.frozen.isFinite && $0.frozen >= 0 && (0..<5).contains($0.slot) }), Set(state.tasks.map(\.id)).count == state.tasks.count else { throw CocoaError(.fileReadCorruptFile) }
                needsLegacyBackup = state.version == 1
                var restored = state.tasks
                for i in restored.indices {
                    if restored[i].reminderLevel == nil { restored[i].reminderLevel = state.version == 1 ? (ReminderLevel(rawValue: state.reminder) ?? .light) : .light }
                    if restored[i].deadline != nil && restored[i].runSequence == nil { restored[i].runSequence = i + 1 }
                }
                tasks = restored; palette = state.palette; menuTaskID = state.menuTaskID
                appearanceMode = state.appearanceMode ?? .auto
                capsulePosition = state.capsulePosition ?? CapsulePosition()
                previewLevel = ["轻提醒","醒目提醒","强打断"].contains(state.reminder) ? state.reminder : "轻提醒"
            } catch { writable = false; storageError = "无法读取保存数据，原文件已保留。请检查：" + self.file.path }
        }
        updateMenuSelection()
        loading = false
    }
    var menuTask: Countdown? { tasks.first { $0.id == menuTaskID && $0.deadline != nil && $0.remaining(at: clock()) > 0 } }
    private func updateMenuSelection() {
        let running = tasks.filter { $0.deadline != nil && $0.remaining(at: clock()) > 0 }
        if running.contains(where: { $0.id == menuTaskID }) { return }
        let id = running.min { ($0.runSequence ?? 0) < ($1.runSequence ?? 0) }?.id
        if menuTaskID != id { menuTaskID = id }
    }
    private var nextRunSequence: Int { (tasks.compactMap(\.runSequence).max() ?? 0) + 1 }
    func selectMenuTask(_ id: UUID) {
        guard tasks.contains(where: { $0.id == id && $0.deadline != nil && $0.remaining(at: clock()) > 0 }) else { return }
        menuTaskID = id
    }
    func cycleReminder(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].reminderLevel = tasks[i].intensity.next
    }
    func move(_ id: UUID, relativeTo target: UUID, after: Bool) {
        guard id != target, let task = tasks.first(where: { $0.id == id }), tasks.contains(where: { $0.id == target }) else { return }
        var reordered = tasks.filter { $0.id != id }
        let index = reordered.firstIndex(where: { $0.id == target })!
        reordered.insert(task, at: index + (after ? 1 : 0)); tasks = reordered
    }
    func moveByKeyboard(_ id: UUID, down: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + (down ? 1 : -1)
        guard tasks.indices.contains(j) else { return }
        move(id, relativeTo: tasks[j].id, after: down)
    }
    func save() {
        guard !loading, writable else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if needsLegacyBackup {
                let backup = file.appendingPathExtension("v1-backup")
                if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: file, to: backup) }
                needsLegacyBackup = false
            }
            let data = try JSONEncoder().encode(SavedState(tasks: tasks, palette: palette, reminder: previewLevel, menuTaskID: menuTaskID, appearanceMode: appearanceMode, capsulePosition: capsulePosition))
            try data.write(to: file, options: .atomic)
            storageError = nil
        } catch { storageError = "保存失败：" + error.localizedDescription }
    }
    func reconcile(recovery: Bool = false) {
        let now = clock()
        let completed = tasks.filter { $0.deadline != nil && $0.remaining(at: now) == 0 }
        guard !completed.isEmpty else { return }
        let ids = Set(completed.map(\.id))
        var updated = tasks
        for i in updated.indices where ids.contains(updated[i].id) { updated[i].deadline = nil; updated[i].frozen = 0 }
        tasks = updated
        onCompletion?(completed, recovery)
    }
    func toggle(_ id: UUID) {
        guard let i = tasks.firstIndex(where: {$0.id == id}) else { return }
        var t = tasks[i]; let r = t.remaining(at: clock())
        if r == 0 { t.deadline = clock().addingTimeInterval(t.duration) }
        else if t.deadline != nil { t.frozen = r; t.deadline = nil }
        else { t.deadline = clock().addingTimeInterval(r) }
        if t.deadline != nil { t.runSequence = nextRunSequence }
        tasks[i] = t
    }
    func reset(_ id: UUID) { guard let i = tasks.firstIndex(where: {$0.id == id}) else { return }; var task = tasks[i]; task.deadline = nil; task.frozen = task.duration; tasks[i] = task }
    func snooze(_ ids: [UUID]) { var updated = tasks; for i in updated.indices where ids.contains(updated[i].id) && updated[i].deadline == nil && updated[i].frozen == 0 { updated[i].duration = 300; updated[i].frozen = 300; updated[i].deadline = clock().addingTimeInterval(300); updated[i].runSequence = nextRunSequence + i }; tasks = updated }
    func remove(_ id: UUID) { tasks.removeAll {$0.id == id} }
    func color(_ id: UUID, _ slot: Int) { guard (0..<5).contains(slot), let i = tasks.firstIndex(where: {$0.id == id}) else { return }; tasks[i].slot = slot }
    func nextColorSlot() -> Int {
        let counts = (0..<5).map { s in tasks.filter {$0.slot == s}.count }
        let choices = (0..<5).filter { counts[$0] == counts.min() }
        let slot = choices.first { $0 != tasks.last?.slot } ?? choices.first ?? 0
        return slot
    }
    func add(_ name: String, minutes: Double, startImmediately: Bool = false) {
        guard minutes.isFinite, minutes >= 1.0/60, minutes <= 1440 else { return }
        let slot = nextColorSlot()
        tasks.append(Countdown(name: name.isEmpty ? "新的倒计时" : String(name.prefix(40)), duration: minutes*60, deadline: startImmediately ? clock().addingTimeInterval(minutes*60) : nil, frozen: minutes*60, slot: slot, reminderLevel: .light, runSequence: startImmediately ? nextRunSequence : nil))
    }
}
func timeText(_ seconds: TimeInterval) -> String { let s = Int(ceil(seconds)); return String(format: "%02d:%02d", s/60, s%60) }

// Match CSS color-mix(in srgb, tone amount%, base).
extension Palette {
    func mixed(_ slot: Int, amount: Double, base: UInt32) -> Color {
        let h = hex[slot % 5]
        func channel(_ shift: UInt32) -> Double {
            (Double((h >> shift) & 255) * amount + Double((base >> shift) & 255) * (1 - amount)) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
    }
    static var muted: Color { Color(.sRGB, red: 97/255, green: 123/255, blue: 124/255, opacity: 1) }
}
