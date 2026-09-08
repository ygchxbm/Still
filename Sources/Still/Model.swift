import SwiftUI
struct Countdown: Identifiable {
    let id = UUID()
    var name: String
    var duration: TimeInterval
    var deadline: Date?
    var frozen: TimeInterval
    var slot: Int
    func remaining(at now: Date) -> TimeInterval { max(0, deadline.map { $0.timeIntervalSince(now) } ?? frozen) }
    func progress(at now: Date) -> Double { min(1, max(0, 1 - remaining(at: now) / duration)) }
}
enum Palette: String, CaseIterable {
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
@MainActor @Observable final class TimerStore {
    var tasks = [Countdown(name: "专注工作", duration: 2400, deadline: Date().addingTimeInterval(1938), frozen: 1938, slot: 0), Countdown(name: "摸鱼休息", duration: 600, deadline: nil, frozen: 600, slot: 1)]
    var palette: Palette = .original
    var reminder = "轻提醒"
    func toggle(_ id: UUID) { guard let i = tasks.firstIndex(where: {$0.id == id}) else { return }; let r = tasks[i].remaining(at: Date()); if r == 0 { tasks[i].deadline = Date().addingTimeInterval(tasks[i].duration) } else if tasks[i].deadline != nil { tasks[i].frozen = r; tasks[i].deadline = nil } else { tasks[i].deadline = Date().addingTimeInterval(r > 0 ? r : tasks[i].duration) } }
    func restart(_ id: UUID) { guard let i = tasks.firstIndex(where: {$0.id == id}) else { return }; tasks[i].deadline = Date().addingTimeInterval(tasks[i].duration) }
    func pin(_ id: UUID) { guard let i = tasks.firstIndex(where: {$0.id == id}) else { return }; tasks.insert(tasks.remove(at: i), at: 0) }
    func remove(_ id: UUID) { tasks.removeAll {$0.id == id} }
    func color(_ id: UUID, _ slot: Int) { guard let i = tasks.firstIndex(where: {$0.id == id}) else { return }; tasks[i].slot = slot }
    func add(_ name: String, minutes: Double) { let counts = (0..<5).map { s in tasks.filter {$0.slot == s}.count }; let slot = (0..<5).min { counts[$0] < counts[$1] } ?? 0; tasks.append(Countdown(name: name.isEmpty ? "新的倒计时" : name, duration: minutes*60, deadline: Date().addingTimeInterval(minutes*60), frozen: minutes*60, slot: slot)) }
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
    func ink(_ slot: Int) -> Color { self == .original ? Color(red: 32/255, green: 54/255, blue: 55/255) : mixed(slot, amount: 0.65, base: 0x152630) }
    func wash(_ slot: Int) -> Color { mixed(slot, amount: 0.14, base: 0xffffff).opacity(0.60) }
}

extension Palette {
    static var muted: Color { Color(.sRGB, red: 97/255, green: 123/255, blue: 124/255, opacity: 1) }
    func statusInk(_ slot: Int) -> Color { self == .original ? Self.muted : mixed(slot, amount: 0.75, base: 0x30475d) }
    func metaInk(_ slot: Int) -> Color {
        if self == .original { return Self.muted }
        let h = hex[slot % 5]
        func channel(_ shift: UInt32) -> Double {
            let ink = Double((h >> shift) & 255) * 0.65 + Double((UInt32(0x152630) >> shift) & 255) * 0.35
            return (ink * 0.78 + Double((UInt32(0x667879) >> shift) & 255) * 0.22) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
    }
}
