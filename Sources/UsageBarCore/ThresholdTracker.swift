import Foundation

/// One "your quota just crossed a threshold" event.
public struct ThresholdAlert: Equatable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case none = 0
        case warning = 1
        case danger = 2

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var service: Service
    public var kind: QuotaWindowKind
    public var level: Level
    public var usedPercent: Double
    public var resetsAt: Date?
}

/// Decides when a notification is due. Pure, so the rules are unit tested and
/// the app side only has to post what this returns.
///
/// Rules:
///   * an alert fires when a window moves *up* into the warning or danger band;
///   * the first reading of a window is only recorded, so launching the app (or
///     enabling a service) at 95% does not announce what the user already sees;
///   * dropping back below a band (the window reset) re-arms it;
///   * failed or stale readings are ignored: kept old numbers must not alert.
public struct ThresholdTracker: Sendable {
    private var levels: [String: ThresholdAlert.Level] = [:]

    public init() {}

    public mutating func alerts(for snapshot: UsageSnapshot,
                                settings: AppSettings,
                                now: Date = Date()) -> [ThresholdAlert] {
        var alerts: [ThresholdAlert] = []
        for service in Service.allCases where settings.isVisible(service) {
            guard let result = snapshot.result(for: service), result.isOK,
                  let usage = result.usage,
                  !usage.isStale(limit: settings.staleAfter, now: now) else { continue }

            for kind in QuotaWindowKind.allCases {
                guard let window = usage.window(kind) else { continue }
                let key = "\(service.rawValue).\(kind.rawValue)"
                let level = Self.level(for: window.usedPercent, settings: settings)
                defer { levels[key] = level }

                guard let previous = levels[key] else { continue }
                if level > previous {
                    alerts.append(ThresholdAlert(service: service,
                                                 kind: kind,
                                                 level: level,
                                                 usedPercent: window.usedPercent,
                                                 resetsAt: window.resetsAt))
                }
            }
        }
        return alerts
    }

    static func level(for usedPercent: Double, settings: AppSettings) -> ThresholdAlert.Level {
        if usedPercent >= settings.dangerThreshold { return .danger }
        if usedPercent >= settings.warnThreshold { return .warning }
        return .none
    }
}
