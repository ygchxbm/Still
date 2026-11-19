import AppKit
@preconcurrency import ApplicationServices

/// Reads only the focused window's full-screen flag and geometry, never its contents.
@MainActor @Observable final class FullscreenMonitor {
    let permission: CapsulePermissionController
    @ObservationIgnored private let foregroundApp: () -> CapsuleTarget?
    @ObservationIgnored private let readWindow: (pid_t) -> FullscreenWindowAccess
    @ObservationIgnored private var previousScreen: NSScreen?
    @ObservationIgnored private var deniedPID: pid_t?

    init(
        permission: CapsulePermissionController = CapsulePermissionController(),
        foregroundApp: @escaping () -> CapsuleTarget? = {
            NSWorkspace.shared.frontmostApplication.map { CapsuleTarget(pid: $0.processIdentifier, name: $0.localizedName ?? "当前 App") }
        },
        readWindow: @escaping (pid_t) -> FullscreenWindowAccess = { FullscreenMonitor.readFocusedWindow($0) }
    ) {
        self.permission = permission
        self.foregroundApp = foregroundApp
        self.readWindow = readWindow
    }

    func refreshPermission() {
        let wasTrusted = permission.globallyTrusted
        permission.refresh()
        if wasTrusted != permission.globallyTrusted { deniedPID = nil }
        if !permission.canInspectForegroundApp { previousScreen = nil }
    }

    func activeScreen() -> NSScreen? {
        refreshPermission()
        guard permission.canInspectForegroundApp, let app = foregroundApp() else { previousScreen = nil; return nil }
        // Opening Still's panel must not dismiss the indicator underneath it.
        if app.pid == ProcessInfo.processInfo.processIdentifier {
            return previousScreen.flatMap { old in NSScreen.screens.first { $0 == old } }
        }
        // A denied app must not trigger a new request on every timer tick.
        // Returning from settings or activating another app clears this cache.
        guard deniedPID != app.pid else { previousScreen = nil; return nil }
        let frame: CGRect
        switch readWindow(app.pid) {
        case .available(let fullScreenFrame):
            permission.recordAccess(.available(app.name))
            guard let fullScreenFrame else { previousScreen = nil; return nil }
            frame = fullScreenFrame
        case .denied:
            deniedPID = app.pid
            permission.recordAccess(.denied(app.name))
            previousScreen = nil
            return nil
        case .unavailable:
            permission.recordAccess(.unavailable(app.name))
            previousScreen = nil
            return nil
        }
        previousScreen = NSScreen.screens.max { a, b in
            Self.overlap(frame, a.frame) < Self.overlap(frame, b.frame)
        }.flatMap { Self.overlap(frame, $0.frame) > 0 ? $0 : nil }
        return previousScreen
    }

    func invalidateScreen() { previousScreen = nil; deniedPID = nil; permission.clearAppContext() }

    private static func readFocusedWindow(_ pid: pid_t) -> FullscreenWindowAccess {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        var focusedWindow: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard status == .success else { return status == .apiDisabled ? .denied : .unavailable }
        guard let focusedWindow, CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else { return .unavailable }
        let window = unsafeDowncast(focusedWindow, to: AXUIElement.self)
        var flag: CFTypeRef?
        let flagStatus = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &flag)
        guard flagStatus != .apiDisabled else { return .denied }
        guard flagStatus == .success else { return .unavailable }
        guard (flag as? Bool) == true else { return .available(nil) }
        guard let positionValue = attribute(window, kAXPositionAttribute as CFString),
              let sizeValue = attribute(window, kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return .unavailable }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
              let primary = NSScreen.screens.first else { return .unavailable }
        // Accessibility coordinates have a top-left origin on the primary screen.
        return .available(CGRect(x: point.x, y: primary.frame.maxY - point.y - size.height, width: size.width, height: size.height))
    }
    private static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }
}

struct CapsuleTarget {
    let pid: pid_t
    let name: String
}

enum FullscreenWindowAccess {
    /// nil means an accessible window that is not full-screen.
    case available(CGRect?)
    case denied
    case unavailable
}
