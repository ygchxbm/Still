import XCTest
@testable import Still

final class Version20Tests: XCTestCase {
    func testMessageDefaultsLimitsAndPlainText() {
        XCTAssertEqual(CompletionMessage.normalized(nil), CompletionMessage.defaultText)
        XCTAssertEqual(CompletionMessage.normalized(" \n\t"), CompletionMessage.defaultText)
        XCTAssertEqual(CompletionMessage.normalized("  <提醒>\n休息一下 & 喝水  "), "<提醒>\n休息一下 & 喝水")
        XCTAssertEqual(CompletionMessage.normalized(String(repeating: "字", count: 81)).utf16.count, 80)
        XCTAssertEqual(CompletionMessage.limited(String(repeating: "😀", count: 41)), String(repeating: "😀", count: 40))
        XCTAssertEqual(CompletionMessage.limited(String(repeating: "字", count: 79) + "😀"), String(repeating: "字", count: 79))
    }

    func testLegacyTaskWithoutMessageStillDecodes() throws {
        let data = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"旧任务\",\"duration\":60,\"frozen\":60,\"slot\":0}".utf8)
        let task = try JSONDecoder().decode(Countdown.self, from: data)
        XCTAssertNil(task.completionMessage)
        XCTAssertEqual(task.completionText, CompletionMessage.defaultText)
        try SavedState(tasks: [task], palette: .original, reminder: "轻提醒").validate()
    }

    @MainActor func testMessagePersistsThroughCompletionExtensionAndRestart() async throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 1000)
        let store = TimerStore(file: file, clock: { now })
        store.add("喝水", minutes: 1, completionMessage: "  起来走走\n喝点水。  ", startImmediately: true)
        let id = store.tasks[0].id
        now += 60
        var received: [Countdown] = []
        store.onCompletion = { tasks, _ in received += tasks }
        store.reconcile()
        XCTAssertEqual(received.first?.completionText, "起来走走\n喝点水。")
        store.snooze(completions: received)
        let restored = TimerStore(file: file, clock: { now })
        XCTAssertEqual(restored.tasks[0].completionText, "起来走走\n喝点水。")
        XCTAssertEqual(restored.tasks[0].originalDuration, 60)
        restored.reset(id)
        restored.toggle(id)
        XCTAssertEqual(restored.tasks[0].completionText, "起来走走\n喝点水。")
        let saved = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
        XCTAssertEqual(saved.version, 2)
        XCTAssertEqual(saved.tasks[0].completionMessage, "起来走走\n喝点水。")
    }

    @MainActor func testBlankNewTaskAndLegacyFileFallback() async throws {
        let file = try temporaryStateFile()
        let legacy = Countdown(name: "旧任务", duration: 60, frozen: 60, slot: 0)
        try JSONEncoder().encode(SavedState(tasks: [legacy], palette: .apple, reminder: "轻提醒")).write(to: file)
        let store = TimerStore(file: file)
        store.add("新任务", minutes: 1, completionMessage: " \n ")
        let restored = TimerStore(file: file)
        XCTAssertNil(restored.storageError)
        XCTAssertEqual(restored.palette, .apple)
        XCTAssertEqual(restored.tasks.map(\.completionText), Array(repeating: CompletionMessage.defaultText, count: 2))
    }

    @MainActor func testPerTaskLevelsNotificationPayloadAndRecoverySummary() async {
        let tasks = ReminderLevel.allCases.enumerated().map { index, level in
            Countdown(name: "任务\(index)", duration: 60, frozen: 0, slot: index, reminderLevel: level, completionMessage: "提示\(index)")
        }
        let events = ReminderController.events(for: tasks)
        XCTAssertEqual(events.map(\.completionText), ["提示0", "提示1", "提示2"])
        XCTAssertEqual(events.map(\.level), ReminderLevel.allCases.map(\.rawValue))
        let content = ReminderController.notificationContent(for: events[0])
        XCTAssertEqual(content.body, "任务0。提示0")
        XCTAssertNil(content.sound)
        let single = ReminderController.events(for: [tasks[1]], recovery: true)[0]
        XCTAssertEqual(single.completionText, "提示1")
        let multiple = ReminderController.events(for: tasks, recovery: true)[0]
        XCTAssertEqual(multiple.completionText, CompletionMessage.defaultText)
        XCTAssertEqual(multiple.level, "轻提醒")
    }

    @MainActor func testDraftPreviewDoesNotCreateOrStartTask() async throws {
        let store = TimerStore(file: try temporaryStateFile())
        store.add("现有任务", minutes: 25)
        let before = store.tasks
        let draft = Countdown(name: "草稿", duration: 60, frozen: 60, slot: store.nextColorSlot(), completionMessage: "草稿提示")
        let event = ReminderController.events(for: [draft], preview: true, previewLevel: ReminderLevel.medium.rawValue)[0]
        XCTAssertTrue(event.preview)
        XCTAssertEqual(event.level, "醒目提醒")
        XCTAssertEqual(event.completionText, "草稿提示")
        XCTAssertNotNil(event.matchingCurrentTasks(store.tasks))
        XCTAssertEqual(store.tasks, before)
        XCTAssertEqual(store.previewLevel, "轻提醒")
        XCTAssertEqual(ReminderController.notificationContent(for: event).title, "留白 · 提醒预览")
    }
}
