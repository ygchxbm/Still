import XCTest
@testable import Still

final class Version17Tests: XCTestCase {
    @MainActor func testOldStateDefaultsToAutomaticAndNewPreferencesRoundTrip() throws {
        let file = try temporaryStateFile()
        try Data(#"{"version":2,"tasks":[],"palette":"原样","reminder":"轻提醒"}"#.utf8).write(to: file)
        let store = TimerStore(file: file)
        XCTAssertEqual(store.appearanceMode, .auto)
        XCTAssertEqual(store.capsulePosition, CapsulePosition())
        store.appearanceMode = .dark
        store.capsulePosition = CapsulePosition(edge: .left, top: 280)
        let restored = TimerStore(file: file)
        XCTAssertNil(restored.storageError)
        XCTAssertEqual(restored.appearanceMode, .dark)
        XCTAssertEqual(restored.capsulePosition, CapsulePosition(edge: .left, top: 280))
        XCTAssertNil(AppearanceMode.auto.appearance)
        XCTAssertEqual(AppearanceMode.light.appearance?.name, .aqua)
        XCTAssertEqual(AppearanceMode.dark.appearance?.name, .darkAqua)
    }
    func testRightAnchorDoesNotMoveWhenExpandedAndPositionClampsOnSmallerDisplay() {
        let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        let position = CapsulePosition(edge: .right, top: 120)
        let small = position.frame(in: screen, size: CGSize(width: 110, height: 44))
        let expanded = position.frame(in: screen, size: CGSize(width: 260, height: 44))
        XCTAssertEqual(small.maxX, expanded.maxX)
        XCTAssertEqual(small.maxY, screen.maxY - 120)
        let clamped = CapsulePosition(edge: .left, top: 5000).frame(in: screen, size: CGSize(width: 110, height: 44))
        XCTAssertEqual(clamped.minX, screen.minX + 12)
        XCTAssertEqual(clamped.minY, screen.minY + 12)
    }
    @MainActor func testCapsuleProgressAndMenuTaskHandoff() throws {
        let file = try temporaryStateFile()
        var now = Date(timeIntervalSince1970: 100)
        let store = TimerStore(file: file, clock: { now })
        store.add("一", minutes: 1, startImmediately: true)
        store.add("二", minutes: 2, startImmediately: true)
        XCTAssertEqual(store.menuTask?.progress(at: now), 0)
        now += 30
        XCTAssertEqual(store.menuTask?.progress(at: now), 0.5)
        now += 30; store.reconcile()
        XCTAssertEqual(store.menuTask?.name, "二")
        store.toggle(store.tasks[1].id)
        XCTAssertNil(store.menuTask)
    }
}
