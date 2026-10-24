import Foundation

/// Builds the text drawn in the menu bar.
///
/// The output is a list of segments rather than one string so the app can colour
/// the numbers (green/amber/red) while tests can assert the plain text. Keeping
/// the layout here means the menu bar and the CLI always agree.
public struct TitleSegment: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        /// Default text colour.
        case normal
        /// At or above the warning threshold.
        case warning
        /// At or above the danger threshold.
        case danger
        /// Prefixes and separators.
        case muted
    }

    public var text: String
    public var severity: Severity
    /// Which service this segment belongs to, when it belongs to one.
    public var service: Service?

    public init(text: String, severity: Severity = .normal, service: Service? = nil) {
        self.text = text
        self.severity = severity
        self.service = service
    }
}

public enum MenuBarTitle {
    /// "Cx 12/48  Cl 8/56" (compact) or "Cx 12%/48%  Cl 8%/56%" (labelled).
    ///
    /// A service that is hidden in settings is skipped entirely; a service that
    /// failed to refresh but has older data still prints the old numbers (the
    /// menu exposes the error) so the menu bar never flickers to an empty state.
    /// Old numbers that are past `AppSettings.staleAfter` are drawn muted, so
    /// months-old data can never pass for a live reading.
    public static func segments(snapshot: UsageSnapshot,
                                settings: AppSettings,
                                now: Date = Date()) -> [TitleSegment] {
        var groups: [[TitleSegment]] = []

        for service in Service.allCases {
            guard settings.isVisible(service) else { continue }

            let result = snapshot.result(for: service)
            var parts: [TitleSegment] = [
                TitleSegment(text: service.shortLabel, severity: .muted, service: service)
            ]

            let values = valuesText(usage: result?.usage, settings: settings)
            let stale = result?.usage?.isStale(limit: settings.staleAfter, now: now) ?? false
            parts.append(TitleSegment(text: " " + values.text,
                                      severity: stale ? .muted : values.severity,
                                      service: service))

            if result?.errorCode != nil {
                parts.append(TitleSegment(text: "!", severity: .danger, service: service))
            }
            groups.append(parts)
        }

        guard !groups.isEmpty else {
            return [TitleSegment(text: "Usage", severity: .muted)]
        }

        var out: [TitleSegment] = []
        for (index, group) in groups.enumerated() {
            if index > 0 {
                out.append(TitleSegment(text: "  ", severity: .muted))
            }
            out.append(contentsOf: group)
        }
        return out
    }

    /// Joined plain text, used for tooltips, logs and the CLI.
    public static func plainText(snapshot: UsageSnapshot,
                                 settings: AppSettings,
                                 now: Date = Date()) -> String {
        segments(snapshot: snapshot, settings: settings, now: now).map(\.text).joined()
    }

    // MARK: - Helpers

    /// Formats the numeric part for one service and derives its severity from the
    /// worst bucket that is currently displayed.
    static func valuesText(usage: ServiceUsage?, settings: AppSettings)
    -> (text: String, severity: TitleSegment.Severity) {
        guard let usage else { return ("–", .normal) }

        /// One value, or an en dash when the plan lacks that window.
        func value(_ window: QuotaWindow?) -> String {
            guard let window else { return "–" }
            return Format.titleValue(window, remaining: settings.showRemaining, style: settings.titleStyle)
        }

        let present: [QuotaWindow?]
        let text: String
        switch settings.displayMode {
        case .both:
            present = [usage.session, usage.weekly]
            text = value(usage.session) + "/" + value(usage.weekly)
        case .session:
            present = [usage.session]
            text = value(usage.session)
        case .weekly:
            present = [usage.weekly]
            text = value(usage.weekly)
        }

        // Nothing to show at all: a single dash beats "–/–".
        guard present.contains(where: { $0 != nil }) else { return ("–", .normal) }

        let worst = present.compactMap { $0?.usedPercent }.max() ?? 0
        return (text, severity(for: worst, settings: settings))
    }

    static func severity(for usedPercent: Double, settings: AppSettings) -> TitleSegment.Severity {
        if usedPercent >= settings.dangerThreshold { return .danger }
        if usedPercent >= settings.warnThreshold { return .warning }
        return .normal
    }
}
