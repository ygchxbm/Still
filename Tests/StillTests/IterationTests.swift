import XCTest
@testable import Still

final class IterationTests: XCTestCase {
    @MainActor func testMenuSelectionIndependentOfOrderAndRestores() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var now = Date(timeIntervalSince1970: 1000)
        let store = TimerStore(file: file, clock: { now })
        for name in ["一", "二", "三"] { store.add(name, minutes: 1) }
        let ids = store.tasks.map(\.id)
        XCTAssertNil(store.menuTask)
        store.selectMenuTask(ids[1]); XCTAssertNil(store.menuTask)
        store.toggle(ids[1]); store.toggle(ids[0]); store.toggle(ids[2])
        XCTAssertEqual(store.menuTask?.id, ids[1])
        store.move(ids[2], relativeTo: ids[0], after: false)
        XCTAssertEqual(store.menuTask?.id, ids[1])
        store.selectMenuTask(ids[2]); XCTAssertEqual(store.menuTask?.id, ids[2])
        XCTAssertEqual(store.tasks.map(\.id), [ids[2], ids[0], ids[1]])
        let restored = TimerStore(file: file, clock: { now })
        XCTAssertEqual(restored.menuTask?.id, ids[2])
        store.toggle(ids[2]); XCTAssertEqual(store.menuTask?.id, ids[1])
        store.toggle(ids[2]); XCTAssertEqual(store.menuTask?.id, ids[1])
        store.remove(ids[1]); XCTAssertEqual(store.menuTask?.id, ids[0])
        store.reset(ids[0]); XCTAssertEqual(store.menuTask?.id, ids[2])
        now += 61; store.reconcile(); XCTAssertNil(store.menuTask)
    }

    @MainActor func testVersionOneMigrationPreservesExistingReminderAndNewTasksAreLight() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let id = UUID()
        let old = """
        {"version":1,"tasks":[{"id":"\(id.uuidString)","name":"原任务","duration":600,"frozen":600,"slot":0}],"palette":"原样","reminder":"强打断"}
        """
        try Data(old.utf8).write(to: file)
        let store = TimerStore(file: file)
        XCTAssertNil(store.storageError)
        XCTAssertEqual(store.tasks[0].intensity, .strong)
        store.add("新任务", minutes: 10)
        XCTAssertEqual(try String(contentsOf: file.appendingPathExtension("v1-backup"), encoding: .utf8), old)
        XCTAssertEqual(store.tasks[1].intensity, .light)
        store.previewLevel = "醒目提醒" // Preview selection never changes task intensities.
        XCTAssertEqual(store.tasks[0].intensity, .strong)
        store.cycleReminder(id); XCTAssertEqual(store.tasks[0].intensity, .light)
        store.cycleReminder(id); XCTAssertEqual(store.tasks[0].intensity, .medium)
        let restored = TimerStore(file: file)
        XCTAssertEqual(restored.tasks[0].intensity, .medium)
        XCTAssertEqual(restored.tasks[1].intensity, .light)
        XCTAssertEqual(try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file)).version, 2)
    }

    @MainActor func testMixedCompletionUsesIndividualLevelsAndPreviewIsIndependent() {
        let tasks = ReminderLevel.allCases.map { level in
            Countdown(name: level.rawValue, duration: 60, frozen: 0, slot: 0, reminderLevel: level)
        }
        let events = ReminderController.events(for: tasks)
        XCTAssertEqual(events.map(\.level), ["轻提醒", "醒目提醒", "强打断"])
        XCTAssertTrue(events.allSatisfy { $0.tasks.count == 1 })
        let recovery = ReminderController.events(for: tasks, recovery: true)
        XCTAssertEqual(recovery.count, 1); XCTAssertEqual(recovery[0].level, "轻提醒")
        XCTAssertEqual(recovery[0].tasks.count, 3)
        let preview = ReminderController.events(for: tasks, preview: true, previewLevel: "醒目提醒")
        XCTAssertEqual(preview[0].level, "醒目提醒")
        XCTAssertEqual(tasks.map(\.intensity), ReminderLevel.allCases)
    }

    @MainActor func testInvalidMovesAndKeyboardBoundariesLeaveStateUnchanged() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = TimerStore(file: file)
        for name in ["一", "二", "三"] { store.add(name, minutes: 1) }
        let ids = store.tasks.map(\.id)
        store.move(ids[0], relativeTo: ids[0], after: true)
        store.move(ids[0], relativeTo: UUID(), after: false)
        store.moveByKeyboard(ids[0], down: false)
        XCTAssertEqual(store.tasks.map(\.id), ids)
        store.moveByKeyboard(ids[0], down: true)
        XCTAssertEqual(store.tasks.map(\.id), [ids[1], ids[0], ids[2]])
        store.move(ids[2], relativeTo: ids[1], after: false)
        XCTAssertEqual(store.tasks.map(\.id), [ids[2], ids[1], ids[0]])
    }
}
