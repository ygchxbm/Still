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
    #if DEBUG
    let store = TimerStore(file: (ProcessInfo.processInfo.environment["STILL_PREVIEW_STATE"] ?? Bundle.main.object(forInfoDictionaryKey: "StillPreviewState") as? String).map { URL(fileURLWithPath: $0) })
    #else
    let store = TimerStore()
    #endif
    private let fullscreen = FullscreenMonitor()
    private lazy var capsule = EdgeCapsuleController(store: store)
    private var capsulePanelScreen: NSScreen?
    private var item: NSStatusItem!
    private let panel = StillPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var outsideMonitor: Any?
    private var timer: Timer?
    private var sleeping = false
    private lazy var reminders = ReminderController(store: store)
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 62)
        item.button?.target = self; item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PanelView(store: store, fullscreen: fullscreen, reminders: reminders, close: { [weak self] in self?.panel.orderOut(nil) }))
        capsule.openPanel = { [weak self] screen in
            guard let self else { return }
            self.store.settingsPresented = false
            self.capsulePanelScreen = screen
            self.positionPanel()
            self.panel.makeKeyAndOrderFront(nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Status-item events can arrive through the global monitor as well.
            // Capture the click position before dispatch; never dismiss the opening click.
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                if self.panel.frame.contains(point) || self.capsule.frame?.contains(point) == true { return }
                if let button = self.item.button, let window = button.window,
                   window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
                self.panel.orderOut(nil)
            }
        }
        reminders.openPanel = { [weak self] in self?.showPanel() }
        store.onCompletion = { [weak self] tasks, recovery in self?.reminders.receive(tasks, recovery: recovery) }
        store.previewReminder = { [weak self] in
            guard let self else { return }
            let task = self.store.tasks.first ?? Countdown(name: "专注工作", duration: 2400, frozen: 0, slot: 0)
            self.reminders.receive([task], preview: true)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        store.reconcile(recovery: true)
        update()
        #if DEBUG
        if ProcessInfo.processInfo.environment["STILL_PREVIEW_STATE"] != nil || Bundle.main.object(forInfoDictionaryKey: "StillPreviewState") != nil { showPanel() }
        #endif
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.update() } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return false }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = item.button {
            let menu = NSMenu()
            let settings = menu.addItem(withTitle: "设置", action: #selector(openSettings), keyEquivalent: "")
            settings.target = self
            menu.addItem(.separator())
            let quit = menu.addItem(withTitle: "退出留白", action: #selector(quitApp), keyEquivalent: "")
            quit.target = self
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else { toggle() }
    }
    @objc private func openSettings() {
        store.settingsPresented = true
        DispatchQueue.main.async { [weak self] in self?.showPanel() }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil); return }
        showPanel()
    }
    private func showPanel() {
        capsulePanelScreen = nil
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    private func positionPanel() {
        guard let button = item.button, let window = button.window, let content = panel.contentView else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = content.fittingSize
        let target = capsulePanelScreen ?? window.screen
        let screen = target?.visibleFrame ?? .zero
        if capsulePanelScreen != nil {
            let x = max(screen.minX + 8, screen.maxX - size.width - 24)
            panel.setFrame(NSRect(x: x, y: screen.maxY - size.height - 8, width: size.width, height: size.height), display: true)
            return
        }
        let x = max(screen.minX + 8, min(anchor.midX - size.width / 2, screen.maxX - size.width - 8))
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height, width: size.width, height: size.height), display: true)
    }
    @objc private func spaceChanged() {
        fullscreen.spaceChanged()
        if capsulePanelScreen != nil { panel.orderOut(nil); capsulePanelScreen = nil }
        update()
    }
    @objc private func willSleep() { sleeping = true; store.save() }
    @objc private func woke() { store.reconcile(recovery: true); sleeping = false; update() }
    func applicationWillTerminate(_ notification: Notification) { store.save() }
    func update() {
        guard !sleeping else { return }
        store.reconcile()
        NSApp.appearance = store.appearanceMode.appearance
        capsule.update(screen: fullscreen.activeScreen())
        if panel.isVisible { positionPanel() }
        guard let button = item.button else { return }
        let now = Date(), task = store.menuTask
        let pulse = reminders.pending && Int(now.timeIntervalSince1970) % 2 == 0
        let referenceText = task.map { timeText($0.remaining(at: now)) } ?? "00:00"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let trackWidth = ceil(referenceText.size(withAttributes: [.font: font]).width)
        let imageWidth = trackWidth + 10
        item.length = imageWidth + 4
        let image = NSImage(size: NSSize(width: imageWidth,height: 23), flipped: false) { [store] bounds in
            let text = pulse ? "到时了" : task.map { timeText($0.remaining(at: now)) } ?? "留白"
            let attrs: [NSAttributedString.Key: Any] = [.font: font,.foregroundColor: NSColor.labelColor]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (imageWidth-size.width)/2,y: 6),withAttributes: attrs)
            NSColor.labelColor.withAlphaComponent(0.15).setFill(); NSBezierPath(roundedRect: NSRect(x: 5,y: 2,width: trackWidth,height: 3),xRadius: 1.5,yRadius: 1.5).fill()
            if let task { NSColor(store.palette.color(task.slot)).setFill(); NSBezierPath(roundedRect: NSRect(x: 5,y: 2,width: trackWidth*task.progress(at: now),height: 3),xRadius: 1.5,yRadius: 1.5).fill() }
            return true
        }
        button.image = image
        button.toolTip = "留白 · 点击打开倒计时"
    }
}
