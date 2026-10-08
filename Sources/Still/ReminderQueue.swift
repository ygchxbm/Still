import Foundation

struct ReminderEvent {
    let id: UUID
    let tasks: [Countdown]
    let level: String
    let recovery: Bool
    let preview: Bool

    init(id: UUID = UUID(), tasks: [Countdown], level: String, recovery: Bool, preview: Bool) {
        self.id = id
        self.tasks = tasks
        self.level = level
        self.recovery = recovery
        self.preview = preview
    }

    func matchingCurrentTasks(_ currentTasks: [Countdown]) -> ReminderEvent? {
        if preview { return self }
        let completed = currentTasks.filter { $0.deadline == nil && $0.frozen == 0 }
        let matching = tasks.filter { task in
            completed.contains { $0.id == task.id && $0.runSequence == task.runSequence }
        }
        guard !matching.isEmpty else { return nil }
        return ReminderEvent(id: id, tasks: matching, level: level, recovery: recovery, preview: false)
    }
}

/// Owns the event lifecycle separately from its AppKit windows.
struct ReminderQueue {
    private var events: [ReminderEvent] = []
    private(set) var active: ReminderEvent?

    mutating func append(_ event: ReminderEvent) { events.append(event) }

    mutating func next(currentTasks: [Countdown], canPresent: Bool = true) -> ReminderEvent? {
        // A display can temporarily disappear during sleep or reconnection.
        // Leave every event queued until it can actually be presented.
        guard active == nil, canPresent else { return nil }
        while !events.isEmpty {
            guard let event = events.removeFirst().matchingCurrentTasks(currentTasks) else { continue }
            active = event
            return event
        }
        return nil
    }

    mutating func finish(id: UUID) -> ReminderEvent? {
        // Other windows from a multi-display reminder may still deliver actions.
        // They must never dismiss or extend the next event in the queue.
        guard let event = active, event.id == id else { return nil }
        active = nil
        return event
    }
}
