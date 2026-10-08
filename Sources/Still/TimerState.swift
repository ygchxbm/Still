import Foundation

enum ReminderLevel: String, Codable, CaseIterable {
    case light = "轻提醒", medium = "醒目提醒", strong = "强打断"
    var next: Self { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
}

struct Countdown: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var duration: TimeInterval
    var deadline: Date?
    var frozen: TimeInterval
    var slot: Int
    var reminderLevel: ReminderLevel?
    var runSequence: Int?
    var originalDuration: TimeInterval?

    var isExtension: Bool { originalDuration != nil }
    var intensity: ReminderLevel { reminderLevel ?? .light }
    func remaining(at now: Date) -> TimeInterval { max(0, deadline.map { $0.timeIntervalSince(now) } ?? frozen) }
    func progress(at now: Date) -> Double { min(1, max(0, 1 - remaining(at: now) / duration)) }

    // A wall-clock adjustment can legitimately make frozen exceed duration.
    // Bound it by Foundation's calendar range, not the task duration.
    static let maximumRemaining = Date.distantFuture.timeIntervalSince(Date.distantPast)
    static let maximumRunSequence = Int.max - 1
    var hasValidStoredValues: Bool {
        duration.isFinite && duration > 0 && duration <= 86400
            && frozen.isFinite && frozen >= 0 && frozen <= Self.maximumRemaining
            && (deadline.map { $0.timeIntervalSinceReferenceDate.isFinite && $0 >= .distantPast && $0 <= .distantFuture } ?? true)
            && (originalDuration.map { $0.isFinite && $0 > 0 && $0 <= 86400 } ?? true)
            && (runSequence.map { $0 > 0 && $0 <= Self.maximumRunSequence } ?? true)
            && (0..<5).contains(slot)
    }
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
}

enum AppearanceMode: String, Codable, CaseIterable {
    case light, dark, auto
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

    func validate() throws {
        guard (1...2).contains(version), tasks.allSatisfy(\.hasValidStoredValues),
              Set(tasks.map(\.id)).count == tasks.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}

func timeText(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "00:00" }
    // Stay safe for invalid values from callers as well as persisted data.
    let value = Int(ceil(min(seconds, Countdown.maximumRemaining)))
    let minutes = String(value / 60)
    let remainder = String(value % 60)
    return (minutes.count < 2 ? "0" : "") + minutes + ":" + (remainder.count < 2 ? "0" : "") + remainder
}
