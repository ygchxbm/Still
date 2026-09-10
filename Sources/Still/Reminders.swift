import AppKit
import SwiftUI
import UserNotifications

struct ReminderEvent {
    let tasks: [Countdown]
    let level: String
    let recovery: Bool
    let preview: Bool
}
struct ReminderQueue {
    private var events: [ReminderEvent] = []
    mutating func append(_ event: ReminderEvent) { events.append(event) }
    mutating func next(currentTasks: [Countdown]) -> ReminderEvent? {
        while !events.isEmpty {
            let event = events.removeFirst()
            if event.preview { return event }
            let eligible = Set(currentTasks.filter { $0.deadline == nil && $0.frozen == 0 }.map(\.id))
            let tasks = event.tasks.filter { eligible.contains($0.id) }
            if !tasks.isEmpty { return ReminderEvent(tasks: tasks, level: event.level, recovery: event.recovery, preview: false) }
        }
        return nil
    }
}
@MainActor @Observable final class ReminderController: NSObject, UNUserNotificationCenterDelegate {
    var pending = false
    var permissionText = "通知权限尚未检查"
    private var queue = ReminderQueue()
    private var windows: [ReminderPanel] = []
    private var active: ReminderEvent?
    private var lightTasks: [Countdown] = []
    private let store: TimerStore
    var openPanel: (() -> Void)?
    init(store: TimerStore) {
        self.store = store
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshPermission()
    }
    func refreshPermission() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: permissionText = "系统通知已允许 · 无声音"
            case .denied: permissionText = "系统通知未允许，菜单栏提醒仍可用"
            case .notDetermined: permissionText = "尚未授权，点击下方允许系统通知"
            @unknown default: permissionText = "通知权限未知"
            }
        }
    }
    func requestPermission() {
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                permissionText = allowed ? "系统通知已允许 · 无声音" : "系统通知未允许，菜单栏提醒仍可用"
            } catch { permissionText = "通知不可用：" + error.localizedDescription }
        }
    }
    func receive(_ tasks: [Countdown], recovery: Bool = false, preview: Bool = false) {
        guard !tasks.isEmpty else { return }
        for event in Self.events(for: tasks, recovery: recovery, preview: preview, previewLevel: store.previewLevel) {
            if event.level == "轻提醒" {
                pending = true
                if !preview { lightTasks += event.tasks }
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
    func acknowledgeLight() { pending = false; lightTasks = []; UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
    var summary: String { lightTasks.isEmpty ? "到时提醒预览" : lightTasks.map(\.name).joined(separator: "、") + " 已完成" }
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
        guard active == nil, let event = queue.next(currentTasks: store.tasks) else { return }
        active = event
        let strong = event.level == "强打断"
        let targets = strong ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        for screen in targets {
            let w = ReminderPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            w.dismissReminder = { [weak self] in self?.finish(snooze: false) }
            w.isReleasedWhenClosed = false; w.isOpaque = false; w.backgroundColor = .clear
            w.hidesOnDeactivate = false; w.level = strong ? .screenSaver : .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.hasShadow = !strong
            w.contentView = NSHostingView(rootView: ReminderView(event: event, tone: store.palette.color(event.tasks[0].slot), strong: strong, done: { [weak self] in self?.finish(snooze: false) }, snooze: { [weak self] in self?.finish(snooze: true) }))
            if strong { w.setFrame(screen.frame, display: true) }
            else { let f = screen.visibleFrame; w.setFrame(NSRect(x: f.midX-220, y: f.midY-170, width: 440, height: 340), display: true) }
            windows.append(w); w.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
    }
    private func finish(snooze: Bool) {
        if snooze, let event = active, !event.preview { store.snooze(event.tasks.map(\.id)) }
        for w in windows { w.orderOut(nil) }
        windows = []; active = nil; presentNext()
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
