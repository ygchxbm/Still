import AppKit
import Observation
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontmostApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
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
        observeStoreChanges()
        store.reconcile(recovery: true)
        update()
        #if DEBUG
        if ProcessInfo.processInfo.environment["STILL_PREVIEW_STATE"] != nil || Bundle.main.object(forInfoDictionaryKey: "StillPreviewState") != nil { showPanel() }
        #endif
        let refreshTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.update() } }
        refreshTimer.tolerance = 0.1
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
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
        // Capture the underlying app before Still becomes active, including when
        // an idle user opens the panel and then starts the first task.
        _ = fullscreen.activeScreen()
        if !panel.isVisible {
            capsulePanelScreen = nil
            positionPanel()
        } else {
            resizeVisiblePanel()
        }
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
    private func resizeVisiblePanel() {
        guard let content = panel.contentView else { return }
        let size = content.fittingSize
        guard panel.frame.size != size else { return }
        // Keep the opening position while allowing settings and task content to change height.
        panel.setFrame(Self.resizedPanelFrame(panel.frame, to: size), display: true)
    }
    static func resizedPanelFrame(_ frame: NSRect, to size: NSSize) -> NSRect {
        NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }
    @objc private func spaceChanged() {
        fullscreen.invalidateScreen()
        if capsulePanelScreen != nil { panel.orderOut(nil); capsulePanelScreen = nil }
        update()
    }
    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        fullscreen.invalidateScreen()
        update()
    }
    @objc private func willSleep() { sleeping = true; store.save() }
    @objc private func woke() { store.reconcile(recovery: true); sleeping = false; update() }
    func applicationDidBecomeActive(_ notification: Notification) {
        fullscreen.refreshPermission()
        reminders.refreshPermission()
        update()
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        store.save()
    }
    private func observeStoreChanges() {
        withObservationTracking {
            _ = store.tasks
            _ = store.menuTaskID
            _ = store.palette
            _ = store.appearanceMode
            _ = store.capsulePosition
            _ = store.settingsPresented
        } onChange: { [weak self] in
            // Observation fires before the mutation. Read the settled state on the
            // next main-actor turn and coalesce synchronous store mutations.
            Task { @MainActor in
                guard let self else { return }
                self.observeStoreChanges()
                self.refreshPresentation()
            }
        }
    }
    func update() {
        guard !sleeping else { return }
        store.reconcile()
        refreshPresentation()
    }
    private func refreshPresentation() {
        guard !sleeping, item != nil else { return }
        let appearance = store.appearanceMode.appearance
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
        let task = store.menuTask
        // With no running menu task the capsule cannot be visible, so do not
        // perform synchronous accessibility queries against another process.
        capsule.update(screen: task == nil ? nil : fullscreen.activeScreen())
        if panel.isVisible { resizeVisiblePanel() }
        guard let button = item.button else { return }
        button.toolTip = "留白 · 点击打开倒计时"
        guard let task else {
            item.length = 28
            button.image = MenuBarCat.image
            return
        }
        let now = Date()
        let text = timeText(task.remaining(at: now))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let size = text.size(withAttributes: [.font: font])
        let trackWidth = ceil(size.width)
        let imageWidth = trackWidth + 10
        item.length = imageWidth + 4
        let image = NSImage(size: NSSize(width: imageWidth,height: 23), flipped: false) { [store] _ in
            let attrs: [NSAttributedString.Key: Any] = [.font: font,.foregroundColor: NSColor.labelColor]
            text.draw(at: NSPoint(x: (imageWidth-size.width)/2,y: 6),withAttributes: attrs)
            NSColor.labelColor.withAlphaComponent(0.15).setFill(); NSBezierPath(roundedRect: NSRect(x: 5,y: 2,width: trackWidth,height: 3),xRadius: 1.5,yRadius: 1.5).fill()
            NSColor(store.palette.color(task.slot)).setFill(); NSBezierPath(roundedRect: NSRect(x: 5,y: 2,width: trackWidth*task.progress(at: now),height: 3),xRadius: 1.5,yRadius: 1.5).fill()
            return true
        }
        button.image = image
    }
}
