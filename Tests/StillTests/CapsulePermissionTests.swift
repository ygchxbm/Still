import XCTest
@testable import Still

final class CapsulePermissionTests: XCTestCase {
    private func version(_ major: Int, _ minor: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }
    private func preferences() throws -> UserDefaults {
        let suite = "StillTests.permissions.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return preferences
    }

    func testVersionBoundaryAndCorrectPrivacyPane() {
        for major in [14, 15, 26] { XCTAssertEqual(CapsulePermissionFlow(version: version(major)), .accessibility) }
        XCTAssertEqual(CapsulePermissionFlow(version: version(27, 2)), .deviceControl)
        for value in [version(27, 3), version(27, 4), version(28)] {
            let flow = CapsulePermissionFlow(version: value)
            XCTAssertEqual(flow, .scopedApps)
            XCTAssertEqual(flow.paneName, "System & App Protection Override")
            XCTAssertEqual(flow.settingsURL.absoluteString, "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
            XCTAssertFalse(flow.settingsURL.absoluteString.contains("Privacy_AccessibilityApps"))
        }
    }

    @MainActor func testModernSetupOpensSettingsWithoutLegacyPromptOrPretendingToGrant() throws {
        let preferences = try preferences()
        var prompts = 0
        var opened: [URL] = []
        let controller = CapsulePermissionController(version: version(27, 3), preferences: preferences, readTrust: { false },
            requestLegacyTrust: { prompts += 1; return true }, openURL: { opened.append($0); return true })
        XCTAssertFalse(controller.canInspectForegroundApp)
        controller.openSettings()
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(opened, [controller.flow.settingsURL])
        XCTAssertTrue(controller.canInspectForegroundApp)
        XCTAssertFalse(controller.globallyTrusted)
        XCTAssertEqual(controller.appAccess, .notChecked)
        XCTAssertTrue(preferences.bool(forKey: CapsulePermissionController.monitoringPreference))
        XCTAssertTrue(controller.instructions.contains("Choose Apps"))
        XCTAssertTrue(controller.instructions.contains("At Any Time"))
        XCTAssertTrue(controller.statusText.contains("重新检测"))
    }

    @MainActor func testLegacyPromptAndExternalPermissionChanges() throws {
        var trusted = false
        var prompts = 0
        let controller = CapsulePermissionController(version: version(26), preferences: try preferences(), readTrust: { trusted },
            requestLegacyTrust: { prompts += 1; return false }, openURL: { _ in true })
        controller.openSettings()
        XCTAssertEqual(prompts, 1)
        XCTAssertFalse(controller.canInspectForegroundApp)
        trusted = true
        controller.refresh()
        XCTAssertTrue(controller.canInspectForegroundApp)
        controller.openSettings()
        XCTAssertEqual(prompts, 1)
        controller.recordAccess(.available("已授权 App"))
        trusted = false
        controller.refresh()
        XCTAssertFalse(controller.canInspectForegroundApp)
        XCTAssertEqual(controller.appAccess, .notChecked)
    }

    @MainActor func testSettingsFallbackAndFailureRemainActionable() throws {
        var opened: [URL] = []
        var rootOpens = true
        let controller = CapsulePermissionController(version: version(27, 3), preferences: try preferences(), readTrust: { false },
            requestLegacyTrust: { XCTFail("Modern flow must not use the legacy prompt"); return false },
            openURL: { url in opened.append(url); return url == CapsulePermissionFlow.privacyURL && rootOpens })
        controller.openSettings()
        XCTAssertEqual(opened, [controller.flow.settingsURL, CapsulePermissionFlow.privacyURL])
        XCTAssertTrue(controller.settingsMessage?.contains(controller.flow.paneName) == true)
        rootOpens = false
        controller.openSettings()
        XCTAssertTrue(controller.settingsMessage?.contains("手动设置") == true)
    }

    @MainActor func testScopedReadWorksWithGlobalTrustFalseAndTracksDenialPerApp() throws {
        let controller = CapsulePermissionController(version: version(27, 3), preferences: try preferences(), readTrust: { false },
            requestLegacyTrust: { false }, openURL: { _ in true })
        var target = CapsuleTarget(pid: -123, name: "允许的 App")
        var result: FullscreenWindowAccess = .available(nil)
        var reads = 0
        let monitor = FullscreenMonitor(permission: controller, foregroundApp: { target }, readWindow: { _ in reads += 1; return result })
        XCTAssertNil(monitor.activeScreen())
        XCTAssertEqual(reads, 0, "Do not start inspecting before the user requests capsule setup")
        controller.openSettings()
        XCTAssertNil(monitor.activeScreen())
        XCTAssertEqual(reads, 1, "Global trust false must not block a scoped read")
        XCTAssertFalse(controller.globallyTrusted)
        XCTAssertEqual(controller.appAccess, .available("允许的 App"))
        target = CapsuleTarget(pid: -124, name: "未允许的 App")
        result = .denied
        monitor.invalidateScreen()
        XCTAssertNil(monitor.activeScreen())
        XCTAssertEqual(controller.appAccess, .denied("未允许的 App"))
        let deniedReads = reads
        XCTAssertNil(monitor.activeScreen())
        XCTAssertEqual(reads, deniedReads, "Do not re-request access on each timer tick after denial")
        result = .unavailable
        monitor.invalidateScreen()
        XCTAssertNil(monitor.activeScreen())
        XCTAssertEqual(controller.appAccess, .unavailable("未允许的 App"))
        result = .available(nil)
        XCTAssertNil(monitor.activeScreen())
        XCTAssertEqual(controller.appAccess, .available("未允许的 App"), "Observe an externally changed grant without restarting")
    }

    @MainActor func testSetupIntentSurvivesRestartWithoutBecomingPermission() throws {
        let preferences = try preferences()
        let first = CapsulePermissionController(version: version(27, 3), preferences: preferences, readTrust: { false }, openURL: { _ in true })
        first.openSettings()
        first.recordAccess(.available("旧窗口"))
        let restored = CapsulePermissionController(version: version(27, 3), preferences: preferences, readTrust: { false }, openURL: { _ in true })
        XCTAssertTrue(restored.canInspectForegroundApp)
        XCTAssertFalse(restored.globallyTrusted)
        XCTAssertEqual(restored.appAccess, .notChecked)
    }

    @MainActor func testLegacyRevocationStopsReadsEvenWithSavedSetupIntent() throws {
        let preferences = try preferences()
        preferences.set(true, forKey: CapsulePermissionController.monitoringPreference)
        var trusted = true
        var reads = 0
        let controller = CapsulePermissionController(version: version(26), preferences: preferences, readTrust: { trusted }, openURL: { _ in true })
        let monitor = FullscreenMonitor(permission: controller, foregroundApp: { CapsuleTarget(pid: -123, name: "目标") }, readWindow: { _ in reads += 1; return .available(nil) })
        _ = monitor.activeScreen()
        XCTAssertEqual(reads, 1)
        trusted = false
        _ = monitor.activeScreen()
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(controller.appAccess, .notChecked)
    }
}
