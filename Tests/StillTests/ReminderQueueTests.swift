import XCTest
@testable import Still
final class ReminderQueueTests: XCTestCase {
    func testQueuePreservesOrderAndSkipsDeletedOrResetTasks() throws {
        let one = Countdown(name: "完成一", duration: 60, frozen: 0, slot: 0)
        var two = Countdown(name: "完成二", duration: 60, frozen: 0, slot: 1)
        let deleted = Countdown(name: "已删除", duration: 60, frozen: 0, slot: 2)
        var q = ReminderQueue()
        q.append(ReminderEvent(tasks: [deleted], level: "强打断", recovery: false, preview: false))
        q.append(ReminderEvent(tasks: [one,two], level: "醒目提醒", recovery: false, preview: false))
        two.frozen = 60
        let next = try XCTUnwrap(q.next(currentTasks: [one,two]))
        XCTAssertEqual(next.tasks.map(\.id), [one.id])
        XCTAssertEqual(next.level, "醒目提醒")
        _ = q.finish(id: next.id)
        XCTAssertNil(q.next(currentTasks: [one,two]))
    }
    func testPreviewAndMultipleBatchesRemainOrdered() throws {
        let one = Countdown(name: "一", duration: 60, frozen: 0, slot: 0)
        let two = Countdown(name: "二", duration: 60, frozen: 0, slot: 1)
        var q = ReminderQueue()
        q.append(ReminderEvent(tasks: [one], level: "醒目提醒", recovery: false, preview: true))
        q.append(ReminderEvent(tasks: [two], level: "强打断", recovery: false, preview: false))
        let preview = try XCTUnwrap(q.next(currentTasks: [two]))
        XCTAssertTrue(preview.preview)
        _ = q.finish(id: preview.id)
        let next = try XCTUnwrap(q.next(currentTasks: [two]))
        XCTAssertEqual(next.tasks.first?.id, two.id)
        _ = q.finish(id: next.id)
        XCTAssertNil(q.next(currentTasks: [two]))
    }

    func testOldCompletionIsSkippedAfterSameTaskCompletesAgain() {
        let old = Countdown(name: "同一任务", duration: 60, frozen: 0, slot: 0, runSequence: 1)
        var current = old
        current.runSequence = 2
        let currentEvent = ReminderEvent(tasks: [current], level: "醒目提醒", recovery: false, preview: false)
        var queue = ReminderQueue()
        queue.append(ReminderEvent(tasks: [old], level: "强打断", recovery: false, preview: false))
        queue.append(currentEvent)

        XCTAssertEqual(queue.next(currentTasks: [current])?.id, currentEvent.id)
        _ = queue.finish(id: currentEvent.id)
        XCTAssertNil(queue.next(currentTasks: [current]))
    }

    func testUnavailableScreenKeepsEventsInOrderAndRevalidatesOnRetry() {
        var one = Countdown(name: "一", duration: 60, frozen: 0, slot: 0, runSequence: 1)
        let two = Countdown(name: "二", duration: 60, frozen: 0, slot: 1, runSequence: 2)
        let first = ReminderEvent(tasks: [one], level: "醒目提醒", recovery: false, preview: false)
        let second = ReminderEvent(tasks: [two], level: "强打断", recovery: false, preview: false)
        var queue = ReminderQueue()
        queue.append(first)
        queue.append(second)

        XCTAssertNil(queue.next(currentTasks: [one, two], canPresent: false))
        XCTAssertNil(queue.active)
        XCTAssertEqual(queue.next(currentTasks: [one, two])?.id, first.id)
        XCTAssertNil(queue.next(currentTasks: [one, two]))
        _ = queue.finish(id: first.id)
        XCTAssertEqual(queue.next(currentTasks: [one, two])?.id, second.id)
        _ = queue.finish(id: second.id)

        queue.append(first)
        queue.append(second)
        XCTAssertNil(queue.next(currentTasks: [one, two], canPresent: false))
        one.frozen = 60
        XCTAssertEqual(queue.next(currentTasks: [one, two])?.id, second.id)
    }

    func testStaleWindowActionsCannotFinishNextEvent() {
        let task = Countdown(name: "完成", duration: 60, frozen: 0, slot: 0)
        let first = ReminderEvent(tasks: [task], level: "醒目提醒", recovery: false, preview: false)
        let second = ReminderEvent(tasks: [task], level: "强打断", recovery: false, preview: true)
        var queue = ReminderQueue()
        queue.append(first)
        queue.append(second)
        XCTAssertEqual(queue.next(currentTasks: [task])?.id, first.id)
        XCTAssertEqual(queue.finish(id: first.id)?.id, first.id)
        XCTAssertEqual(queue.next(currentTasks: [task])?.id, second.id)

        XCTAssertNil(queue.finish(id: first.id))
        XCTAssertEqual(queue.active?.id, second.id)
        XCTAssertEqual(queue.finish(id: second.id)?.id, second.id)
        XCTAssertNil(queue.finish(id: second.id))
    }
}
