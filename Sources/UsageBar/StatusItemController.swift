import AppKit
import UsageBarCore

/// The single `NSStatusItem` that owns the menu bar slot.
///
/// Only drawing lives here. The controller receives an already fetched snapshot
/// plus the user's settings and renders them; it never performs network work.
final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    /// Asked for a fresh menu on every click, so the dropdown is never a stale
    /// copy and "Refresh Now" can be disabled while a fetch is in flight.
    var menuProvider: (() -> NSMenu)?

    private var font: NSFont

    init(fontSize: Double) {
        font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = font
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick)
        statusItem.behavior = .removalAllowed
    }

    /// Pops the menu programmatically. Assigning `statusItem.menu` for the
    /// duration of the click is the standard trick that lets a left click open
    /// the menu without the button action firing twice.
    @objc private func handleClick() {
        guard let menu = menuProvider?() else { return }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Applies new settings without recreating the status item (which would make
    /// the icon blink and lose its position).
    func apply(fontSize: Double) {
        font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        statusItem.button?.font = font
    }

    /// Renders "Cx 12/48  Cl 8/56" with per-segment colours.
    func render(snapshot: UsageSnapshot, settings: AppSettings, isRefreshing: Bool) {
        guard let button = statusItem.button else { return }

        let segments = MenuBarTitle.segments(snapshot: snapshot, settings: settings)
        let title = NSMutableAttributedString()
        for segment in segments {
            title.append(NSAttributedString(string: segment.text, attributes: [
                .font: font,
                .foregroundColor: color(for: segment.severity)
            ]))
        }

        // A dimmed ellipsis while a refresh is in flight: subtle, no icon swap.
        if isRefreshing {
            title.append(NSAttributedString(string: " …", attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor
            ]))
        }

        button.attributedTitle = title
        button.toolTip = tooltip(snapshot: snapshot)
        button.appearsDisabled = false

        Log.debug("render: \"\(title.string)\" visible=\(statusItem.isVisible) "
                  + "frame=\(NSStringFromRect(button.frame))")
    }

    /// Detailed hover text: what each number means, plus reset countdowns and
    /// any error the last refresh produced.
    private func tooltip(snapshot: UsageSnapshot) -> String {
        var lines: [String] = []
        for service in Service.allCases {
            guard let result = snapshot.result(for: service) else { continue }
            var line = service.displayName
            if let usage = result.usage {
                let session = usage.session.map { Format.percent($0.usedPercent) } ?? "–"
                let weekly = usage.weekly.map { Format.percent($0.usedPercent) } ?? "–"
                line += "  5h \(session) · week \(weekly)"
                if let plan = usage.plan { line += "  (\(plan))" }
            }
            if let code = result.errorCode {
                line += "\n  " + L.describe(code: code, detail: result.errorDetail)
            }
            lines.append(line)
        }
        if lines.isEmpty { return "UsageBar" }
        lines.append(L.t("menu.updated", Format.clock(snapshot.updatedAt)))
        return lines.joined(separator: "\n")
    }

    private func color(for severity: TitleSegment.Severity) -> NSColor {
        switch severity {
        case .normal:  return .labelColor
        case .warning: return .systemOrange
        case .danger:  return .systemRed
        case .muted:   return .secondaryLabelColor
        }
    }
}
