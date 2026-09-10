import XCTest
@testable import Still
final class ReminderQueueTests: XCTestCase {
    func testQueuePreservesOrderAndSkipsDeletedOrResetTasks() {
        let one = Countdown(name: "完成一", duration: 60, frozen: 0, slot: 0)
        var two = Countdown(name: "完成二", duration: 60, frozen: 0, slot: 1)
        let deleted = Countdown(name: "已删除", duration: 60, frozen: 0, slot: 2)
        var q = ReminderQueue()
        q.append(ReminderEvent(tasks: [deleted], level: "强打断", recovery: false, preview: false))
        q.append(ReminderEvent(tasks: [one,two], level: "醒目提醒", recovery: false, preview: false))
        two.frozen = 60
        let next = q.next(currentTasks: [one,two])
        XCTAssertEqual(next?.tasks.map(\.id), [one.id])
        XCTAssertEqual(next?.level, "醒目提醒")
        XCTAssertNil(q.next(currentTasks: [one,two]))
    }
    func testPreviewAndMultipleBatchesRemainOrdered() {
        let one = Countdown(name: "一", duration: 60, frozen: 0, slot: 0)
        let two = Countdown(name: "二", duration: 60, frozen: 0, slot: 1)
        var q = ReminderQueue()
        q.append(ReminderEvent(tasks: [one], level: "醒目提醒", recovery: false, preview: true))
        q.append(ReminderEvent(tasks: [two], level: "强打断", recovery: false, preview: false))
        XCTAssertTrue(q.next(currentTasks: [two])?.preview == true)
        XCTAssertEqual(q.next(currentTasks: [two])?.tasks.first?.id, two.id)
        XCTAssertNil(q.next(currentTasks: [two]))
    }
}
