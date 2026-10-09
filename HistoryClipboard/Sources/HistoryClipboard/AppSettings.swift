import Foundation
import Observation

enum RetentionDays: Int, CaseIterable {
    case one = 1
    case three = 3
    case five = 5

    var title: String { "\(rawValue) 天" }
    var timeInterval: TimeInterval { TimeInterval(rawValue * 86400) }
    var cutoffTimestamp: TimeInterval { Date().timeIntervalSince1970 - timeInterval }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: .standard)
    private let defaults: UserDefaults

    var retentionDays: RetentionDays {
        didSet { defaults.set(retentionDays.rawValue, forKey: "retentionDays") }
    }
    var isMonitoringPaused: Bool {
        didSet { defaults.set(isMonitoringPaused, forKey: "isMonitoringPaused") }
    }
    var excludedApplicationIDs: String {
        didSet { defaults.set(excludedApplicationIDs, forKey: "excludedApplicationIDs") }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        retentionDays = RetentionDays(rawValue: defaults.integer(forKey: "retentionDays")) ?? .three
        isMonitoringPaused = defaults.bool(forKey: "isMonitoringPaused")
        excludedApplicationIDs = defaults.string(forKey: "excludedApplicationIDs") ?? ""
    }

    func excludesApplication(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApplicationIDs.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(bundleID)
    }
}
