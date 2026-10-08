import AppKit
import ServiceManagement
import Observation

/// System registration is the source of truth; no separate preference is persisted.
@MainActor @Observable final class LoginItemController {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?
    private(set) var isUpdating = false
    @ObservationIgnored private let readStatus: () -> SMAppService.Status
    @ObservationIgnored private let register: () throws -> Void
    @ObservationIgnored private let unregister: () async throws -> Void

    init(
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () async throws -> Void = { try await SMAppService.mainApp.unregister() }
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        refresh()
    }

    var isRequested: Bool { status == .enabled || status == .requiresApproval }
    var message: String {
        switch status {
        case .enabled: "已开启，登录后在菜单栏后台运行。"
        case .requiresApproval: "需要在系统设置中允许留白登录时启动。"
        case .notRegistered: "登录后在菜单栏后台运行，不自动打开任务面板。"
        case .notFound: "无法找到登录项，请从完整的留白应用中设置。"
        @unknown default: "无法确定登录项状态，请检查系统设置。"
        }
    }

    func refresh() { status = readStatus() }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        refresh()
        isUpdating = true
        errorMessage = nil
        defer { refresh(); isUpdating = false }
        do {
            if enabled {
                if !isRequested { try register() }
            } else if isRequested {
                try await unregister()
            }
        } catch {
            errorMessage = "无法更新登录自启：" + error.localizedDescription
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
