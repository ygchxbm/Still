import AppKit
import SwiftUI
@main enum StillMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TimerStore()
    private var item: NSStatusItem!
    private let panel = StillPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    private var outsideMonitor: Any?
    private var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 62)
        item.button?.target = self; item.button?.action = #selector(toggle)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PanelView(store: store, close: { [weak self] in self?.panel.orderOut(nil) }))
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Status-item events can arrive through the global monitor as well.
            // Capture the click position before dispatch; never dismiss the opening click.
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                if self.panel.frame.contains(point) { return }
                if let button = self.item.button, let window = button.window,
                   window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
                self.panel.orderOut(nil)
            }
        }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.update() } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return false }
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil); return }
        showPanel()
    }
    private func showPanel() {
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    private func positionPanel() {
        guard let button = item.button, let window = button.window, let content = panel.contentView else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = content.fittingSize
        let screen = window.screen?.visibleFrame ?? .zero
        let x = max(screen.minX + 8, min(anchor.midX - size.width / 2, screen.maxX - size.width - 8))
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height, width: size.width, height: size.height), display: true)
    }
    func update() {
        if panel.isVisible { positionPanel() }
        guard let button = item.button else { return }
        let now = Date(), task = store.tasks.first
        let image = NSImage(size: NSSize(width: 58,height: 23), flipped: false) { [store] bounds in
            let text = task.map { timeText($0.remaining(at: now)) } ?? "留白"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13,weight: .semibold),.foregroundColor: NSColor.labelColor]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (58-size.width)/2,y: 6),withAttributes: attrs)
            NSColor.labelColor.withAlphaComponent(0.15).setFill(); NSBezierPath(roundedRect: NSRect(x: 5,y: 2,width: 48,height: 3),xRadius: 1.5,yRadius: 1.5).fill()
            if let task { NSColor(store.palette.color(task.slot)).setFill(); NSBezierPath(roundedRect: NSRect(x: 5,y: 2,width: 48*task.progress(at: now),height: 3),xRadius: 1.5,yRadius: 1.5).fill() }
            return true
        }
        button.image = image
        button.toolTip = "留白 · 点击打开倒计时"
    }
}
