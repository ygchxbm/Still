import AppKit
@preconcurrency import ApplicationServices
import Observation

/// The 27.3 pane separates assistive technology from ordinary cross-app access.
/// Reading its public AX API can succeed for one app even when global trust is false.
enum CapsulePermissionFlow {
    case accessibility, deviceControl, scopedApps

    init(version: OperatingSystemVersion) {
        if version.majorVersion > 27 || (version.majorVersion == 27 && version.minorVersion >= 3) {
            self = .scopedApps
        } else if version.majorVersion == 27 {
            self = .deviceControl
        } else {
            self = .accessibility
        }
    }

    var paneName: String {
        switch self {
        case .accessibility: "辅助功能"
        case .deviceControl: "设备控制与数据访问（Device Control and Data Access）"
        // This beta still uses the English name in the Simplified Chinese UI.
        case .scopedApps: "System & App Protection Override"
        }
    }
    var settingsURL: URL {
        let bundle = self == .accessibility ? "com.apple.preference.security" : "com.apple.settings.PrivacySecurity.extension"
        return URL(string: "x-apple.systempreferences:\(bundle)?Privacy_Accessibility")!
    }
    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!
}

enum CapsuleAppAccess: Equatable {
    case notChecked
    case available(String)
    case denied(String)
    case unavailable(String)
}

@MainActor @Observable final class CapsulePermissionController {
    static let monitoringPreference = "capsuleMonitoringRequested"
    let flow: CapsulePermissionFlow
    private(set) var globallyTrusted: Bool
    private(set) var monitoringRequested: Bool
    private(set) var appAccess: CapsuleAppAccess = .notChecked
    private(set) var settingsMessage: String?
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let readTrust: () -> Bool
    @ObservationIgnored private let requestLegacyTrust: () -> Bool
    @ObservationIgnored private let openURL: (URL) -> Bool

    init(
        version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        preferences: UserDefaults = .standard,
        readTrust: @escaping () -> Bool = { AXIsProcessTrusted() },
        requestLegacyTrust: @escaping () -> Bool = {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        flow = CapsulePermissionFlow(version: version)
        self.preferences = preferences
        self.readTrust = readTrust
        self.requestLegacyTrust = requestLegacyTrust
        self.openURL = openURL
        globallyTrusted = readTrust()
        monitoringRequested = preferences.bool(forKey: Self.monitoringPreference)
    }

    var canInspectForegroundApp: Bool {
        globallyTrusted || (flow == .scopedApps && monitoringRequested)
    }
    var actionTitle: String {
        if flow == .scopedApps { return "设置胶囊权限" }
        return globallyTrusted ? "管理胶囊权限" : "授权胶囊权限"
    }
    var statusText: String {
        // Report actual reads before global trust: a grant may have been revoked,
        // or the frontmost app may temporarily have no accessible window.
        switch appAccess {
        case .available(let name): return "已能检测“\(name)”的窗口；全屏计时时显示胶囊。"
        case .denied(let name): return "暂时无法访问“\(name)”的窗口，请检查该 App 的胶囊访问权限。"
        case .unavailable(let name): return "“\(name)”暂未提供可检测的窗口，尚无法确认访问状态。"
        case .notChecked: break
        }
        if globallyTrusted { return "已获得窗口访问权限，全屏计时时显示胶囊。" }
        if flow == .scopedApps {
            return monitoringRequested
                ? "设置后请切回已允许的 App 并开始计时，留白会重新检测。"
                : "全屏胶囊需要窗口访问权限，可仅允许你常用的 App。"
        }
        return "允许窗口访问后，可在全屏计时时显示倒计时胶囊。"
    }
    var instructions: String {
        let path = "系统设置 → 隐私与安全 → \(flow.paneName)"
        if flow == .scopedApps {
            return "1. 打开\(path)。\n2. 点击＋添加当前运行的 Still／留白，再点“选取 App（Choose Apps）”，选择需要显示胶囊的 App。\n3. 如需自动检测，将所选 App 设为“At Any Time（随时）”；选择“Ask First”时，可能需要先回应系统询问。\n4. 切回已允许的 App，开始倒计时并进入全屏。\n此版本的“无障碍”页面用于屏幕阅读器等应用，留白不在该页添加。"
        }
        return "1. 打开\(path)。\n2. 在列表中允许 Still／留白；若未列出，点击＋添加当前运行的应用。\n3. 返回留白，再切到目标 App 开始计时并进入全屏。"
    }
    var purposeText: String {
        "留白仅读取前台窗口的全屏状态、位置和大小，用于放置胶囊。不读取窗口内容，也不发送键盘或鼠标操作。"
    }

    func refresh() {
        let current = readTrust()
        if globallyTrusted != current { globallyTrusted = current; appAccess = .notChecked }
    }
    func recordAccess(_ access: CapsuleAppAccess) {
        if appAccess != access { appAccess = access }
    }
    func clearAppContext() { recordAccess(.notChecked) }

    func openSettings() {
        settingsMessage = nil
        // Intent to inspect is persisted separately from the OS grant. It never
        // constitutes permission, and the OS still authorizes each AX read.
        monitoringRequested = true
        preferences.set(true, forKey: Self.monitoringPreference)
        if flow != .scopedApps && !globallyTrusted { _ = requestLegacyTrust() }
        refresh()
        if openURL(flow.settingsURL) { return }
        if openURL(CapsulePermissionFlow.privacyURL) {
            settingsMessage = "已打开隐私与安全，请选择“\(flow.paneName)”。"
        } else {
            settingsMessage = "无法打开系统设置，请按下方授权步骤手动设置。"
        }
    }

    func revealApplication() {
        let application = Bundle.main.bundleURL
        guard application.pathExtension.lowercased() == "app" else {
            settingsMessage = "请从打包的 Still.app 启动后再定位应用。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([application])
    }
}
