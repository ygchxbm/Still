import XCTest
@testable import Still
final class TimerStoreTests: XCTestCase {
    @MainActor func testPersistencePauseAndResume() async throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 1000)
        let store = TimerStore(file: file, clock: { now })
        store.add("工作", minutes: 40, startImmediately: true)
        let id = try XCTUnwrap(store.tasks.first?.id)
        now += 120; store.toggle(id)
        store.palette = .apple; store.previewLevel = "强打断"; store.color(id, 3)
        now += 3600
        let restored = TimerStore(file: file, clock: { now })
        XCTAssertEqual(restored.tasks[0].id, id)
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 2280, accuracy: 0.01)
        XCTAssertEqual(restored.palette, .apple); XCTAssertEqual(restored.previewLevel, "强打断")
        XCTAssertEqual(restored.tasks[0].slot, 3)
        restored.toggle(id); now += 80
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 2200, accuracy: 0.01)
    }
    @MainActor func testRecoveryAndSingleCompletion() async throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 2000)
        let store = TimerStore(file: file, clock: { now }); store.add("一", minutes: 1, startImmediately: true); store.add("二", minutes: 2, startImmediately: true)
        now += 300
        let restored = TimerStore(file: file, clock: { now })
        var events = 0
        restored.onCompletion = { tasks, recovery in events += 1; XCTAssertEqual(tasks.count, 2); XCTAssertTrue(recovery) }
        restored.reconcile(recovery: true); restored.reconcile()
        XCTAssertEqual(events, 1)
        let again = TimerStore(file: file, clock: { now })
        again.onCompletion = { _, _ in XCTFail("重复完成") }; again.reconcile(recovery: true)
        let id = again.tasks[0].id; again.reset(id)
        XCTAssertEqual(again.tasks[0].remaining(at: now), 60)
        XCTAssertNil(again.tasks[0].deadline)
        now += 30
        XCTAssertEqual(again.tasks[0].remaining(at: now), 60)
        let resetRestored = TimerStore(file: file, clock: { now })
        XCTAssertNil(resetRestored.tasks[0].deadline)
        resetRestored.toggle(id)
        now += 10
        XCTAssertEqual(resetRestored.tasks[0].remaining(at: now), 50)
    }
    @MainActor func testCorruptFilePreservedAndInvalidDurationRejected() async throws {
        let file = try temporaryStateFile(), bytes = Data("broken".utf8)
        try bytes.write(to: file)
        let store = TimerStore(file: file)
        XCTAssertNotNil(store.storageError)
        store.add("无效", minutes: .nan, startImmediately: true); store.add("无效", minutes: -1, startImmediately: true)
        XCTAssertTrue(store.tasks.isEmpty)
        store.add("有效", minutes: 1, startImmediately: true)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    @MainActor func testOrderColorDeleteSnoozePersist() async throws {
        let file = try temporaryStateFile()
        var now = Date()
        let store = TimerStore(file: file, clock: { now })
        for i in 0..<5 { store.add("任务\(i)", minutes: 2, startImmediately: true) }
        XCTAssertEqual(Set(store.tasks.map(\.slot)).count, 5)
        now += 121; store.reconcile()
        let completed = store.tasks[4]
        let id = completed.id
        store.move(id, relativeTo: store.tasks[0].id, after: false)
        store.snooze(completions: [completed]); store.remove(store.tasks[1].id)
        let restored = TimerStore(file: file, clock: { now })
        XCTAssertEqual(restored.tasks.first?.id, id); XCTAssertEqual(restored.tasks.count, 4)
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 300)
    }
    @MainActor func testOldReminderCannotOverwriteRestartedOrResetTask() async throws {
        let file = try temporaryStateFile()
        var now = Date()
        let store = TimerStore(file: file, clock: { now })
        store.add("专注", minutes: 40, startImmediately: true)
        let id = store.tasks[0].id
        now += 2401; store.reconcile()
        let completed = store.tasks[0]
        store.reset(id); store.snooze(completions: [completed])
        XCTAssertEqual(store.tasks[0].duration, 2400)
        XCTAssertNil(store.tasks[0].deadline)
        store.toggle(id); let deadline = store.tasks[0].deadline
        store.snooze(completions: [completed])
        XCTAssertEqual(store.tasks[0].deadline, deadline)
        XCTAssertEqual(store.tasks[0].duration, 2400)
    }
    @MainActor func testNewTaskWaitsUntilStartedAndRestores() async throws {
        let file = try temporaryStateFile()
        var now = Date()
        let store = TimerStore(file: file, clock: { now })
        store.add("等待开始", minutes: 25)
        now += 600
        let restored = TimerStore(file: file, clock: { now })
        XCTAssertNil(restored.tasks[0].deadline)
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 1500)
        restored.toggle(restored.tasks[0].id); now += 5
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 1495)
    }
}
