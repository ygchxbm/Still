import AppKit
import SwiftUI
import UserNotifications

@MainActor @Observable final class ReminderController: NSObject, UNUserNotificationCenterDelegate {
    var permissionText = "通知权限尚未检查"
    private var queue = ReminderQueue()
    private var windows: [ReminderPanel] = []
    private let store: TimerStore
    var openPanel: (() -> Void)?
    init(store: TimerStore) {
        self.store = store
        super.init()
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refreshPermission()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    func refreshPermission() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: permissionText = "系统通知已允许 · 无声音"
            case .denied: permissionText = "系统通知未允许，轻提醒将无法显示"
            case .notDetermined: permissionText = "尚未授权，点击下方允许系统通知"
            @unknown default: permissionText = "通知权限未知"
            }
        }
    }
    func requestPermission() {
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                permissionText = allowed ? "系统通知已允许 · 无声音" : "系统通知未允许，轻提醒将无法显示"
            } catch { permissionText = "通知不可用：" + error.localizedDescription }
        }
    }
    func receive(_ tasks: [Countdown], recovery: Bool = false, preview: Bool = false) {
        guard !tasks.isEmpty else { return }
        for event in Self.events(for: tasks, recovery: recovery, preview: preview, previewLevel: store.previewLevel) {
            if event.level == "轻提醒" {
                notify(event)
            } else { queue.append(event) }
        }
        presentNext()
    }
    static func events(for tasks: [Countdown], recovery: Bool = false, preview: Bool = false, previewLevel: String = "轻提醒") -> [ReminderEvent] {
        if tasks.isEmpty { return [] }
        if recovery || preview { return [ReminderEvent(tasks: tasks, level: recovery ? "轻提醒" : previewLevel, recovery: recovery, preview: preview)] }
        return tasks.map { ReminderEvent(tasks: [$0], level: $0.intensity.rawValue, recovery: false, preview: false) }
    }
    private func notify(_ event: ReminderEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.recovery ? "离开期间的倒计时已完成" : event.preview ? "留白 · 提醒预览" : "留白 · 时间到了"
        content.body = event.tasks.map(\.name).joined(separator: "、") + "。起来走走，或回到下一段专注。"
        content.sound = nil
        Task {
            do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
            catch { permissionText = "通知发送失败：" + error.localizedDescription }
        }
    }
    private func presentNext() {
        let screens = NSScreen.screens
        guard let event = queue.next(currentTasks: store.tasks, canPresent: !screens.isEmpty) else { return }
        let strong = event.level == "强打断"
        let targets = strong ? screens : [NSScreen.main ?? screens[0]]
        for screen in targets {
            let w = ReminderPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            w.dismissReminder = { [weak self] in self?.finish(eventID: event.id, snooze: false) }
            w.isReleasedWhenClosed = false; w.isOpaque = false; w.backgroundColor = .clear
            w.hidesOnDeactivate = false; w.level = strong ? .screenSaver : .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.hasShadow = !strong
            w.contentView = NSHostingView(rootView: ReminderView(event: event, tone: store.palette.color(event.tasks[0].slot), strong: strong, done: { [weak self] in self?.finish(eventID: event.id, snooze: false) }, snooze: { [weak self] in self?.finish(eventID: event.id, snooze: true) }))
            if strong { w.setFrame(screen.frame, display: true) }
            else { let f = screen.visibleFrame; w.setFrame(NSRect(x: f.midX-220, y: f.midY-170, width: 440, height: 340), display: true) }
            windows.append(w); w.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
    }
    @objc private func screenParametersDidChange() { presentNext() }
    private func finish(eventID: UUID, snooze: Bool) {
        guard let event = queue.finish(id: eventID) else { return }
        let closingWindows = windows
        windows = []
        for w in closingWindows {
            w.dismissReminder = nil
            w.contentView = nil
            w.close()
        }
        if snooze, !event.preview { store.snooze(completions: event.tasks) }
        presentNext()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in self?.openPanel?() }
        completionHandler()
    }
}
final class ReminderPanel: NSPanel {
    var dismissReminder: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismissReminder?() }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { dismissReminder?() } else { super.keyDown(with: event) } }
}
struct ReminderView: View {
    let event: ReminderEvent
    let tone: Color
    let strong: Bool
    let done: () -> Void
    let snooze: () -> Void
    var body: some View {
        ZStack {
            if strong { Rectangle().fill(.ultraThinMaterial).overlay(tone.opacity(0.16)).ignoresSafeArea() }
            VStack(spacing: 20) {
                Text(event.preview ? "提醒效果预览" : "倒计时完成").font(.caption).foregroundStyle(tone)
                Image(systemName: "figure.walk").font(.system(size: 44, weight: .light)).foregroundStyle(tone)
                Text(event.tasks.first?.name.contains("休息") == true ? "休息结束，回到节奏。" : "做得很好，起来走走。").font(.system(size: 23, weight: .semibold))
                ScrollView { Text(event.tasks.map(\.name).joined(separator: " · ")).multilineTextAlignment(.center).frame(maxWidth: .infinity) }.frame(maxHeight: 45)
                HStack(spacing: 16) {
                    if !event.preview { Button("再加 5 分钟", action: snooze) }
                    Button(event.preview ? "结束预览" : "知道了，完成", action: done).buttonStyle(.borderedProminent).tint(tone)
                }
                Text("按 Esc 可退出 · 无声音").font(.caption2).foregroundStyle(.secondary)
            }.padding(28).frame(width: 430).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).overlay { RoundedRectangle(cornerRadius: 24).stroke(tone.opacity(0.25)) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
