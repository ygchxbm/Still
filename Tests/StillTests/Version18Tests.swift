import XCTest
@testable import Still

final class Version18Tests: XCTestCase {
    @MainActor func testExtensionSurvivesReloadAndRestoresOriginalDuration() async throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 1000)
        let store = TimerStore(file: file, clock: { now })
        store.add("专注", minutes: 25, startImmediately: true)
        let id = store.tasks[0].id
        now += 1500; store.reconcile(); store.snooze(completions: [store.tasks[0]])
        XCTAssertEqual(store.tasks[0].originalDuration, 1500)
        XCTAssertEqual(store.tasks[0].duration, 300)
        XCTAssertEqual(store.tasks[0].progress(at: now), 0)
        now += 150
        XCTAssertEqual(store.tasks[0].progress(at: now), 0.5)
        store.toggle(id)
        let restored = TimerStore(file: file, clock: { now })
        XCTAssertEqual(restored.tasks[0].originalDuration, 1500)
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 150)
        restored.toggle(id); now += 150; restored.reconcile()
        XCTAssertNil(restored.menuTask)
        restored.snooze(completions: [restored.tasks[0]])
        XCTAssertEqual(restored.tasks[0].originalDuration, 1500)
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 300)
        now += 300; restored.reconcile(); restored.toggle(id)
        XCTAssertEqual(restored.tasks[0].duration, 1500)
        XCTAssertNil(restored.tasks[0].originalDuration)
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 1500)
        now += 1500; restored.reconcile(); restored.snooze(completions: [restored.tasks[0]]); restored.reset(id)
        XCTAssertEqual(restored.tasks[0].remaining(at: now), 1500)
        XCTAssertNil(restored.tasks[0].originalDuration)
        XCTAssertNil(restored.tasks[0].deadline)
    }

    @MainActor func testLegacyTaskAndTemplateIcon() async throws {
        let data = Data("{\"name\":\"旧任务\",\"id\":\"00000000-0000-0000-0000-000000000001\",\"duration\":1500,\"frozen\":1500,\"slot\":0}".utf8)
        let task = try JSONDecoder().decode(Countdown.self, from: data)
        XCTAssertNil(task.originalDuration)
        XCTAssertFalse(task.isExtension)
        XCTAssertTrue(MenuBarCat.image.isTemplate)
        XCTAssertEqual(MenuBarCat.image.size.width, 20)
        XCTAssertNotNil(MenuBarCat.image.tiffRepresentation)
    }
}
