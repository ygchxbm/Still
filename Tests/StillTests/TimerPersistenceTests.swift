import XCTest
@testable import Still

final class TimerPersistenceTests: XCTestCase {
    @MainActor func testTaskTransitionsWriteOneCompleteSnapshot() throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 2000)
        var snapshots: [SavedState] = []
        let store = TimerStore(file: file, clock: { now }, writer: { data, _ in
            snapshots.append(try JSONDecoder().decode(SavedState.self, from: data))
        })
        store.add("任务", minutes: 1, startImmediately: true)
        let id = try XCTUnwrap(store.tasks.first?.id)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.last?.menuTaskID, id)
        store.toggle(id)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertNil(snapshots.last?.tasks.first?.deadline)
        XCTAssertNil(snapshots.last?.menuTaskID)
        store.toggle(id)
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots.last?.menuTaskID, id)
        now += 61
        store.reconcile()
        XCTAssertEqual(snapshots.count, 4)
        XCTAssertEqual(snapshots.last?.tasks.first?.frozen, 0)
        XCTAssertNil(snapshots.last?.menuTaskID)
        store.snooze(completions: [store.tasks[0]])
        XCTAssertEqual(snapshots.count, 5)
        store.reset(id)
        XCTAssertEqual(snapshots.count, 6)
        store.reset(id)
        store.selectMenuTask(id)
        store.remove(UUID())
        store.palette = .original
        XCTAssertEqual(snapshots.count, 6, "No-op commands must not write")
    }

    @MainActor func testCompletionWaitsForSuccessfulSaveAndRecoverySurvivesRetry() throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 2000)
        var failing = false
        var writes = 0
        let store = TimerStore(file: file, clock: { now }, writer: { data, url in
            writes += 1
            if failing { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        })
        store.add("恢复任务", minutes: 1, startImmediately: true)
        let runningBytes = try Data(contentsOf: file)
        var callbacks = 0
        store.onCompletion = { tasks, recovery in
            callbacks += 1
            XCTAssertTrue(recovery)
            XCTAssertEqual(tasks.count, 1)
            // The durable snapshot must already be complete when delivery starts.
            let disk = try? JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
            XCTAssertNil(disk?.tasks.first?.deadline)
            XCTAssertEqual(disk?.tasks.first?.frozen, 0)
        }
        now += 61
        failing = true
        store.reconcile(recovery: true)
        XCTAssertNotNil(store.storageError)
        XCTAssertNotNil(store.tasks.first?.deadline)
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(try Data(contentsOf: file), runningBytes)
        failing = false
        store.reconcile()
        XCTAssertEqual(callbacks, 1)
        XCTAssertNil(store.storageError)
        XCTAssertEqual(writes, 3)
        store.reconcile()
        XCTAssertEqual(writes, 3)
        let restored = TimerStore(file: file, clock: { now })
        restored.onCompletion = { _, _ in XCTFail("Completed state must not redeliver after restart") }
        restored.reconcile(recovery: true)
    }

    @MainActor func testFailedRecoveryDoesNotDowngradeANewerRun() throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 2000)
        var failing = false
        let store = TimerStore(file: file, clock: { now }, writer: { _, _ in
            if failing { throw CocoaError(.fileWriteNoPermission) }
        })
        store.add("任务", minutes: 1, startImmediately: true)
        let id = try XCTUnwrap(store.tasks.first?.id)
        now += 61
        failing = true
        store.reconcile(recovery: true)
        failing = false
        store.toggle(id)
        now += 61
        var callbacks = 0
        store.onCompletion = { _, recovery in callbacks += 1; XCTAssertFalse(recovery) }
        store.reconcile()
        XCTAssertEqual(callbacks, 1)
    }

    @MainActor func testFailedCompletionSaveStillHandsOffMenuSelection() throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 2000)
        var failing = false
        var writes = 0
        let store = TimerStore(file: file, clock: { now }, writer: { _, _ in
            writes += 1
            if failing { throw CocoaError(.fileWriteNoPermission) }
        })
        store.add("先到期", minutes: 1, startImmediately: true)
        store.add("仍在运行", minutes: 2, startImmediately: true)
        let secondID = store.tasks[1].id
        now += 61
        failing = true
        store.reconcile()
        XCTAssertNotNil(store.tasks[0].deadline, "Retain completion for retry")
        XCTAssertEqual(store.menuTaskID, secondID)
        XCTAssertEqual(store.menuTask?.id, secondID)
        XCTAssertEqual(writes, 3, "Menu handoff must not trigger another write")
    }

    @MainActor func testInvalidNumericFieldsPreserveOriginalFile() throws {
        let fields = ["\"frozen\":1e300", "\"frozen\":-1", "\"deadline\":1e300",
                      "\"runSequence\":9223372036854775807", "\"runSequence\":-1"]
        for field in fields {
            let file = try temporaryStateFile()
            let frozen = field.hasPrefix("\"frozen\"") ? "" : ",\"frozen\":60"
            let json = "{\"version\":2,\"tasks\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"task\",\"duration\":60,\"slot\":0\(frozen),\(field)}],\"palette\":\"原样\",\"reminder\":\"轻提醒\"}"
            let bytes = Data(json.utf8)
            try bytes.write(to: file)
            let store = TimerStore(file: file)
            XCTAssertNotNil(store.storageError, field)
            XCTAssertTrue(store.tasks.isEmpty, field)
            store.add("新任务", minutes: 1)
            XCTAssertFalse(store.save())
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    @MainActor func testWallClockRollbackAndLargeSafeSequenceRemainValid() throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 2000)
        let store = TimerStore(file: file, clock: { now })
        store.add("任务", minutes: 1, startImmediately: true)
        let id = try XCTUnwrap(store.tasks.first?.id)
        now -= 3600
        store.toggle(id)
        XCTAssertEqual(store.tasks[0].frozen, 3660)
        let restored = TimerStore(file: file, clock: { now })
        XCTAssertNil(restored.storageError)
        XCTAssertEqual(restored.tasks[0].frozen, 3660)

        var state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
        state.tasks[0].runSequence = Int.max - 2
        try JSONEncoder().encode(state).write(to: file)
        let nearLimit = TimerStore(file: file, clock: { now })
        nearLimit.toggle(id)
        XCTAssertEqual(nearLimit.tasks[0].runSequence, Int.max - 1)
        nearLimit.toggle(id)
        nearLimit.toggle(id)
        XCTAssertNotNil(nearLimit.storageError)
        XCTAssertNil(nearLimit.tasks[0].deadline)
        XCTAssertNil(TimerStore(file: file, clock: { now }).storageError)
    }

    @MainActor func testOldCompletionCannotSnoozeANewerCompletedRun() throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 2000)
        let store = TimerStore(file: file, clock: { now })
        store.add("目标", minutes: 1, startImmediately: true)
        let id = try XCTUnwrap(store.tasks.first?.id)
        now += 61
        store.reconcile()
        let old = store.tasks[0]
        store.toggle(id)
        store.add("序号最高", minutes: 1, startImmediately: true)
        let highest = try XCTUnwrap(store.tasks.last?.runSequence)
        store.remove(store.tasks[1].id)
        now += 61
        store.reconcile()
        store.snooze(completions: [old])
        XCTAssertNil(store.tasks[0].deadline)
        let latest = store.tasks[0]
        store.snooze(completions: [latest])
        XCTAssertGreaterThan(try XCTUnwrap(store.tasks[0].runSequence), highest)
        XCTAssertEqual(store.tasks[0].duration, 300)
    }

    func testTimeTextHandlesFractionalNegativeAndExtremeInputs() {
        XCTAssertEqual(timeText(0), "00:00")
        XCTAssertEqual(timeText(-1), "00:00")
        XCTAssertEqual(timeText(.nan), "00:00")
        XCTAssertEqual(timeText(.infinity), "00:00")
        XCTAssertEqual(timeText(0.1), "00:01")
        XCTAssertEqual(timeText(59.1), "01:00")
        XCTAssertEqual(timeText(6000), "100:00")
        XCTAssertEqual(timeText(60 * 2_000_000_000), "2000000000:00")
        XCTAssertEqual(timeText(Double.greatestFiniteMagnitude), timeText(Countdown.maximumRemaining))
    }
}
