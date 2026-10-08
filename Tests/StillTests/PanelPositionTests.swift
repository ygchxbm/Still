import XCTest
@testable import Still

final class PanelPositionTests: XCTestCase {
    @MainActor func testContentResizePreservesLeftAndTopEdges() async {
        let initial = CGRect(x: 740, y: 300, width: 322, height: 500)
        let settings = AppDelegate.resizedPanelFrame(initial, to: CGSize(width: 322, height: 600))
        XCTAssertEqual(settings.minX, initial.minX)
        XCTAssertEqual(settings.maxY, initial.maxY)
        XCTAssertEqual(settings.height, 600)
        let restored = AppDelegate.resizedPanelFrame(settings, to: initial.size)
        XCTAssertEqual(restored, initial)
    }
}
