import AppKit
@preconcurrency import ApplicationServices

/// Reads only the focused window's full-screen flag and geometry, never its contents.
@MainActor @Observable final class FullscreenMonitor {
    var trusted = AXIsProcessTrusted()
    @ObservationIgnored private var previousScreen: NSScreen?

    func refreshPermission() {
        let current = AXIsProcessTrusted()
        if trusted != current { trusted = current }
        if !trusted { previousScreen = nil }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
    }

    func activeScreen() -> NSScreen? {
        refreshPermission()
        guard trusted, let app = NSWorkspace.shared.frontmostApplication else { previousScreen = nil; return nil }
        // Opening Still's panel must not dismiss the indicator underneath it.
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return previousScreen.flatMap { old in NSScreen.screens.first { $0 == old } }
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let value = attribute(application, kAXFocusedWindowAttribute as CFString),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { previousScreen = nil; return nil }
        let window = unsafeDowncast(value, to: AXUIElement.self)
        guard (attribute(window, "AXFullScreen" as CFString) as? Bool) == true,
              let positionValue = attribute(window, kAXPositionAttribute as CFString),
              let sizeValue = attribute(window, kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            previousScreen = nil; return nil
        }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
              let primary = NSScreen.screens.first else { previousScreen = nil; return nil }
        // Accessibility coordinates have a top-left origin on the primary screen.
        let frame = CGRect(x: point.x, y: primary.frame.maxY - point.y - size.height, width: size.width, height: size.height)
        previousScreen = NSScreen.screens.max { a, b in
            Self.overlap(frame, a.frame) < Self.overlap(frame, b.frame)
        }.flatMap { Self.overlap(frame, $0.frame) > 0 ? $0 : nil }
        return previousScreen
    }

    func invalidateScreen() { previousScreen = nil }
    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }
}
