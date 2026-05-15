import Foundation

enum RetentionDays: Int, CaseIterable {
    case one = 1
    case three = 3
    case five = 5

    var title: String {
        switch self {
        case .one: return "1 天"
        case .three: return "3 天"
        case .five: return "5 天"
        }
    }

    var timeInterval: TimeInterval {
        TimeInterval(rawValue * 86400)
    }

    var cutoffTimestamp: TimeInterval {
        Date().timeIntervalSince1970 - timeInterval
    }
}

final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let retentionKey = "retentionDays"

    var retentionDays: RetentionDays {
        get {
            let raw = defaults.integer(forKey: retentionKey)
            return RetentionDays(rawValue: raw) ?? .three
        }
        set {
            defaults.set(newValue.rawValue, forKey: retentionKey)
        }
    }

    private init() {}
}
