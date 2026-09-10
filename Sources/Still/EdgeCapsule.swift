import AppKit
import SwiftUI

@MainActor final class EdgeCapsuleController {
    private let store: TimerStore
    private let panel = StillPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let content = CapsuleContentView()
    private var screen: NSScreen?
    var openPanel: ((NSScreen) -> Void)?
    var frame: CGRect? { panel.isVisible ? panel.frame : nil }

    init(store: TimerStore) {
        self.store = store
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false; panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        // Dock-like native glass: let the system render refraction and its rim.
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.cornerRadius = 22
            glass.focusRingType = .none
            glass.contentView = content
            panel.contentView = glass
        } else {
            let glass = NSVisualEffectView()
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 22
            glass.layer?.masksToBounds = true
            glass.focusRingType = .none
            glass.addSubview(content)
            content.autoresizingMask = [.width, .height]
            panel.contentView = glass
        }
        content.expansionChanged = { [weak self] in self?.position() }
        content.clicked = { [weak self] in
            guard let self, let screen = self.screen else { return }
            self.openPanel?(screen)
        }
        content.dragEnded = { [weak self] in
            guard let self, let screen = self.screen else { return }
            self.store.capsulePosition = CapsulePosition(edge: self.panel.frame.midX < screen.frame.midX ? .left : .right, top: screen.frame.maxY - self.panel.frame.maxY)
            self.position()
        }
    }
    func update(screen: NSScreen?) {
        guard let screen, let task = store.menuTask else { content.resetHover(); panel.orderOut(nil); self.screen = nil; return }
        self.screen = screen
        content.task = task; content.palette = store.palette
        // Follow the app appearance preference; automatic mode inherits the system.
        panel.appearance = store.appearanceMode.appearance
        content.needsDisplay = true
        position()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    private func position() {
        guard let screen, !content.dragging else { return }
        let width = content.preferredWidth
        let frame = store.capsulePosition.frame(in: screen.frame, size: CGSize(width: width, height: 44))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        let contentFrame = CGRect(origin: .zero, size: panel.frame.size)
        if content.frame != contentFrame { content.frame = contentFrame }
    }
}

private final class CapsuleContentView: NSView {
    var task: Countdown?
    var palette = Palette.original
    var expansionChanged: (() -> Void)?
    var clicked: (() -> Void)?
    var dragEnded: (() -> Void)?
    private var hovered = false
    private var down: CGPoint?
    private var originalFrame = CGRect.zero
    private(set) var dragging = false
    private var tracking: NSTrackingArea?
    private var expanded: Bool { hovered }
    private let textFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { super.init(coder: coder); focusRingType = .none }
    func resetHover() {
        if hovered || dragging { NSCursor.arrow.set() }
        hovered = false
        dragging = false
        down = nil
        needsDisplay = true
    }
    var preferredWidth: CGFloat {
        let timeWidth = (timeText(task?.remaining(at: Date()) ?? 0) as NSString).size(withAttributes: [.font: textFont]).width
        let nameWidth = expanded ? min(160, ((task?.name ?? "") as NSString).size(withAttributes: [.font: textFont]).width) + 12 : 0
        return 60 + timeWidth + nameWidth
    }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(visibleRect, cursor: dragging ? .closedHand : .pointingHand)
    }
    private func refreshCursor() {
        (dragging ? NSCursor.closedHand : hovered ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect follows resizing automatically; replacing it can generate
        // stale exit events while the name expands or the window changes position.
        if tracking == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
            tracking = area
            addTrackingArea(area)
        }
    }
    private func updateHoverFromPointer() {
        let inside = window.map {
            $0.isVisible && bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil))
        } ?? false
        if hovered != inside {
            hovered = inside
            expansionChanged?()
            needsDisplay = true
        }
        refreshCursor()
    }
    override func cursorUpdate(with event: NSEvent) { updateHoverFromPointer() }
    override func mouseMoved(with event: NSEvent) { updateHoverFromPointer() }
    override func mouseEntered(with event: NSEvent) { updateHoverFromPointer() }
    override func mouseExited(with event: NSEvent) { updateHoverFromPointer() }
    override func mouseDown(with event: NSEvent) { down = NSEvent.mouseLocation; originalFrame = window?.frame ?? .zero; dragging = false; refreshCursor() }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let point = NSEvent.mouseLocation
        if hypot(point.x - down.x, point.y - down.y) > 5 { dragging = true }
        if dragging { window?.setFrameOrigin(CGPoint(x: originalFrame.minX + point.x - down.x, y: originalFrame.minY + point.y - down.y)) }
        refreshCursor()
    }
    override func mouseUp(with event: NSEvent) {
        guard down != nil else { return }
        down = nil
        let moved = dragging; dragging = false
        if moved { dragEnded?() } else { clicked?() }
        // Edge snapping can move the capsule away from the pointer.
        if let window {
            hovered = window.isVisible && bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else { hovered = false }
        expansionChanged?()
        needsDisplay = true
        refreshCursor()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { clicked?() }
        else if event.keyCode == 53 { window?.makeFirstResponder(nil) }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { clicked?(); return true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "\(task?.name ?? "倒计时")，剩余 \(timeText(task?.remaining(at: Date()) ?? 0))，打开任务面板" }
    override func draw(_ dirtyRect: NSRect) {
        guard let task else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // No painted background: preserve the native glass material.
        let color = NSColor(dark ? palette.mixed(task.slot, amount: 0.55, base: 0xffffff) : palette.color(task.slot))
        let center = CGPoint(x: 26, y: bounds.midY)
        let track = NSBezierPath(ovalIn: CGRect(x: 13, y: center.y - 13, width: 26, height: 26))
        track.lineWidth = 3; color.withAlphaComponent(0.18).setStroke(); track.stroke()
        let progress = task.progress(at: Date())
        if progress > 0 {
            let arc = NSBezierPath(); arc.lineWidth = 3; arc.lineCapStyle = .round
            arc.appendArc(withCenter: center, radius: 13, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
            color.setStroke(); arc.stroke()
        }
        let time = timeText(task.remaining(at: Date())) as NSString
        let textHeight = time.size(withAttributes: [.font: textFont]).height
        let textY = bounds.midY - textHeight / 2
        var x: CGFloat = 48
        if expanded {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            let width = preferredWidth - 60 - (timeText(task.remaining(at: Date())) as NSString).size(withAttributes: [.font: textFont]).width - 12
            (task.name as NSString).draw(in: CGRect(x: x, y: textY, width: width, height: textHeight), withAttributes: [.font: textFont, .foregroundColor: color, .paragraphStyle: paragraph])
            x += width + 12
        }
        (timeText(task.remaining(at: Date())) as NSString).draw(at: CGPoint(x: x, y: textY), withAttributes: [.font: textFont, .foregroundColor: color])
    }
}
