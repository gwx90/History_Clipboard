import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemManager {
    static let shared = LoginItemManager(defaults: .standard)
    private let defaults: UserDefaults
    private let statusProvider: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let configuredKey = "loginItemWasConfigured"
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    init(defaults: UserDefaults, statusProvider: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.defaults = defaults
        self.statusProvider = statusProvider
        self.register = register
        self.unregister = unregister
        status = statusProvider()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var statusDescription: String {
        switch status {
        case .enabled: return "已启用开机自启"
        case .notRegistered: return "开机自启已关闭"
        case .requiresApproval: return "等待系统批准，请在系统设置的登录项中允许此 App。"
        case .notFound: return "无法找到登录项，请从完整的 .app 应用运行。"
        @unknown default: return "无法确认登录项状态"
        }
    }

    func refreshStatus() { status = statusProvider() }
    func clearError() { errorMessage = nil }

    func prepareDefaultRegistration() {
        refreshStatus()
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        if status == .notRegistered { setEnabled(true) }
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: configuredKey)
        refreshStatus()
        do {
            if enabled && !isEnabled { try register() }
            else if !enabled && status != .notRegistered { try unregister() }
            refreshStatus()
            errorMessage = nil
        } catch {
            refreshStatus()
            errorMessage = error.localizedDescription
        }
    }
}
