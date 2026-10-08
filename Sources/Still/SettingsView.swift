import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: TimerStore
    var fullscreen: FullscreenMonitor
    var reminders: ReminderController
    @State private var loginItem = LoginItemController()
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { scheme == .dark ? Color(red: 0.49, green: 0.79, blue: 0.74) : Color(red: 0.16, green: 0.48, blue: 0.44) }
    private var surface: Color { scheme == .dark ? .white.opacity(0.045) : .white.opacity(0.28) }
    private var line: Color { scheme == .dark ? .white.opacity(0.10) : .white.opacity(0.55) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Button { store.settingsPresented = false } label: {
                        Label("返回", systemImage: "chevron.left").font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(.secondary).accessibilityLabel("返回倒计时")
                    Text("设置").font(.system(size: 14, weight: .semibold))
                    Spacer()
                }.padding(.top, 2)

                section("启动") {
                    Toggle("登录时自动启动", isOn: Binding(
                        get: { loginItem.isRequested },
                        set: { enabled in Task { await loginItem.setEnabled(enabled) } }
                    ))
                    .toggleStyle(.switch)
                    .font(.system(size: 12))
                    .tint(accent)
                    .disabled(loginItem.isUpdating)
                    hint(loginItem.message)
                    if let error = loginItem.errorMessage {
                        Text(error).font(.system(size: 10)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                    if loginItem.status == .requiresApproval || loginItem.errorMessage != nil {
                        Button("打开系统登录项设置") { loginItem.openSystemSettings() }
                            .buttonStyle(SettingsActionStyle(accent: accent))
                    }
                }

                section("显示模式") {
                    HStack(spacing: 6) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            let selected = store.appearanceMode == mode
                            Button { store.appearanceMode = mode } label: {
                                Label(mode.title, systemImage: mode.icon)
                                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                    .frame(maxWidth: .infinity).frame(height: 36)
                                    .modifier(SettingsControlSurface(accent: accent, selected: selected))
                            }.accessibilityAddTraits(selected ? [.isSelected] : [])
                        }
                    }.accessibilityElement(children: .contain).accessibilityLabel("显示模式")
                }

                section("外观配色") {
                    hint("每套五色；任务的色位保持不变。")
                    VStack(spacing: 4) {
                        ForEach(Palette.allCases, id: \.self) { palette in
                            let selected = store.palette == palette
                            Button { store.palette = palette } label: {
                                HStack {
                                    Text(palette.rawValue).font(.system(size: 12, weight: selected ? .medium : .regular))
                                    Spacer(minLength: 8)
                                    HStack(spacing: 6) {
                                        ForEach(0..<5) { slot in
                                            Circle().fill(palette.color(slot)).frame(width: 8, height: 8)
                                        }
                                    }.accessibilityHidden(true)
                                }.padding(.horizontal, 12).frame(height: 42)
                                    .modifier(SettingsControlSurface(accent: accent, selected: selected, row: true))
                            }.accessibilityLabel(palette.rawValue).accessibilityAddTraits(selected ? [.isSelected] : [])
                        }
                    }.padding(4).background(surface, in: RoundedRectangle(cornerRadius: 14))
                }

                section("提醒效果预览") {
                    Menu {
                        ForEach(ReminderLevel.allCases, id: \.self) { level in
                            Button(reminderTitle(level)) { store.previewLevel = level.rawValue }
                        }
                    } label: {
                        HStack {
                            Text(reminderTitle(ReminderLevel(rawValue: store.previewLevel) ?? .light))
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        }.font(.system(size: 11))
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).frame(height: 36)
                        .modifier(SettingsControlSurface(accent: accent))
                        .accessibilityLabel("提醒效果预览").accessibilityValue(store.previewLevel)
                    hint("仅用于预览，不改变任务提醒强度 · 无声音")
                    Button { store.previewReminder?() } label: {
                        HStack {
                            Text("预览到时提醒")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                    }.buttonStyle(SettingsActionStyle(accent: accent))
                }

                VStack(alignment: .leading, spacing: 9) {
                    Rectangle().fill(line).frame(height: 1).padding(.bottom, 5)
                    HStack(spacing: 8) {
                        Button { fullscreen.requestPermission() } label: {
                            Label("全屏胶囊", systemImage: "capsule")
                        }.buttonStyle(SettingsActionStyle(accent: accent))
                            .disabled(fullscreen.trusted)
                            .help(fullscreen.trusted ? "已授权，全屏且有运行任务时自动显示" : "授权辅助功能以启用全屏胶囊")
                        Button { reminders.requestPermission() } label: {
                            Label("通知授权", systemImage: "bell.badge")
                        }.buttonStyle(SettingsActionStyle(accent: accent))
                    }
                    hint(fullscreen.trusted ? "全屏胶囊已授权" : "全屏胶囊需要辅助功能授权")
                    hint(reminders.permissionText.replacingOccurrences(of: "点击下方允许系统通知", with: "点击“通知授权”开启"))
                    Button { NSApp.terminate(nil) } label: {
                        Label("退出留白", systemImage: "power").frame(maxWidth: .infinity)
                    }.buttonStyle(SettingsActionStyle(accent: accent, destructive: true))
                        .padding(.top, 3)
                }
                hint("关闭面板后计时继续，设置自动保存。")
                    .frame(maxWidth: .infinity, alignment: .center)
            }.padding(.horizontal, 2).padding(.bottom, 8)
        }.frame(height: 470)
            .buttonStyle(HandButtonStyle())
            .onAppear {
                loginItem.refresh()
                fullscreen.refreshPermission()
                reminders.refreshPermission()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                loginItem.refresh()
            }
    }

    private func reminderTitle(_ level: ReminderLevel) -> String {
        switch level {
        case .light: "轻提醒 · 系统通知"
        case .medium: "醒目提醒 · 中央卡片"
        case .strong: "强打断 · 全屏遮罩"
        }
    }
    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
        }
    }
}

// All settings controls share these state colors and cursor behavior.
private struct SettingsControlSurface: ViewModifier {
    var accent: Color
    var selected = false
    var destructive = false
    var row = false
    var pressed = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    private var tint: Color {
        destructive ? (scheme == .dark ? Color(red: 1, green: 0.51, blue: 0.55) : Color(red: 0.72, green: 0.19, blue: 0.26)) : accent
    }
    private var fill: Color {
        if selected || destructive {
            return tint.opacity(pressed ? 0.23 : hovered ? 0.19 : 0.13)
        }
        if pressed { return accent.opacity(0.17) }
        if hovered { return accent.opacity(0.09) }
        if row { return .clear }
        return .white.opacity(scheme == .dark ? 0.045 : 0.28)
    }
    func body(content: Content) -> some View {
        content
            .foregroundStyle(selected || destructive ? tint : .primary)
            .background(fill, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(
                    row ? .clear : selected || destructive ? tint.opacity(0.35) : .white.opacity(scheme == .dark ? 0.10 : 0.55)
                )
            }
            .opacity(enabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { hovered = enabled && $0 }
            .modifier(HandCursor())
    }
}

private struct SettingsActionStyle: ButtonStyle {
    var accent: Color
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .frame(maxWidth: .infinity).padding(.horizontal, 12).frame(height: 36)
            .modifier(SettingsControlSurface(accent: accent, destructive: destructive, pressed: configuration.isPressed))
    }
}
