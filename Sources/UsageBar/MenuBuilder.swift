import AppKit
import UsageBarCore

/// Builds the dropdown menu for the current state.
///
/// Rows are plain `NSMenuItem`s with attributed titles: a custom view would look
/// nicer but breaks keyboard navigation, VoiceOver and the menu highlight, and
/// text renders crisply enough with a monospaced font.
enum MenuBuilder {
    /// Everything the menu needs; passed as one value so the builder stays pure
    /// and the app delegate owns the state.
    struct Context {
        var snapshot: UsageSnapshot
        var settings: AppSettings
        var isRefreshing: Bool
        var launchAtLogin: Bool
        var onRefresh: () -> Void
        var onSettings: () -> Void
        var onToggleLaunchAtLogin: () -> Void
        var onOpenFolder: () -> Void
        var onOpenSetup: () -> Void
        var onQuit: () -> Void
    }

    static func build(_ context: Context) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for service in Service.allCases where context.settings.isVisible(service) {
            appendService(service, context: context, to: menu)
        }

        // First-run help. Only offered when a service genuinely lacks credentials,
        // so it never becomes permanent menu noise for a working install.
        if needsCredentialHelp(context) {
            menu.addItem(action(title: L.t("menu.loginHelp"), key: "", handler: context.onOpenSetup))
        }

        menu.addItem(.separator())

        // Last refresh attempt. `updatedAt` moves on every attempt, failed or
        // not, so staleness is judged from each service's own `fetchedAt`: the
        // line turns amber when any visible service is showing kept old numbers.
        let now = Date()
        let stale = Service.allCases.contains { service in
            guard context.settings.isVisible(service),
                  let usage = context.snapshot.result(for: service)?.usage else { return false }
            return usage.isStale(limit: context.settings.staleAfter, now: now)
        }
        let updated = context.snapshot.updatedAt == .distantPast
            ? L.t("menu.never")
            : L.t(stale ? "menu.checkedStale" : "menu.checked", Format.clock(context.snapshot.updatedAt))
        let freshness = NSMenuItem(title: updated, action: nil, keyEquivalent: "")
        freshness.attributedTitle = NSAttributedString(string: updated, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: stale ? NSColor.systemOrange : NSColor.secondaryLabelColor
        ])
        menu.addItem(freshness)

        menu.addItem(.separator())
        menu.addItem(action(title: context.isRefreshing ? L.t("menu.refreshing") : L.t("menu.refresh"),
                            key: "r",
                            enabled: !context.isRefreshing,
                            handler: context.onRefresh))
        menu.addItem(action(title: L.t("menu.settings"), key: ",", handler: context.onSettings))
        menu.addItem(action(title: L.t("menu.launchAtLogin"),
                            key: "",
                            checked: context.launchAtLogin,
                            handler: context.onToggleLaunchAtLogin))
        menu.addItem(action(title: L.t("menu.openFolder"), key: "", handler: context.onOpenFolder))
        menu.addItem(.separator())
        menu.addItem(action(title: L.t("menu.quit"), key: "q", handler: context.onQuit))

        return menu
    }

    // MARK: - Service section

    private static func appendService(_ service: Service,
                                      context: Context,
                                      to menu: NSMenu) {
        let result = context.snapshot.result(for: service)

        // Header: "Codex · prolite"
        var headerText = service.displayName
        if let plan = result?.usage?.plan, !plan.isEmpty {
            headerText += "  ·  " + plan
        }
        if context.settings.showRemaining, result?.usage != nil {
            headerText += "  ·  " + L.t("menu.remaining")
        }
        let header = NSMenuItem(title: headerText, action: nil, keyEquivalent: "")
        let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        header.attributedTitle = NSAttributedString(string: headerText, attributes: [
            .font: headerFont,
            .foregroundColor: NSColor.labelColor
        ])
        header.image = NSImage(systemSymbolName: service.symbolName, accessibilityDescription: service.displayName)
        menu.addItem(header)

        if let usage = result?.usage {
            let rowFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            for kind in QuotaWindowKind.allCases {
                guard let window = usage.window(kind) else {
                    let text = "   " + pad(kind.shortLabel, 5) + L.t("menu.noWindow")
                    menu.addItem(disabled(text, font: rowFont, color: .tertiaryLabelColor))
                    continue
                }
                menu.addItem(row(window: window,
                                 font: rowFont,
                                 settings: context.settings))
            }

            // Model scoped weekly buckets (Claude Opus / Sonnet) only appear when
            // the account actually reports them.
            for window in usage.scoped {
                let label = window.scope ?? "Model"
                menu.addItem(row(window: window, font: rowFont, settings: context.settings, label: label))
            }

            // Provider notes ("limit reached", "credits 3"). The vendor's own
            // words stay English except the one we have a translation for.
            if !usage.notes.isEmpty {
                let text = usage.notes
                    .map { $0 == "limit reached" ? L.t("menu.limitReached") : $0 }
                    .joined(separator: "  ·  ")
                menu.addItem(disabled("   " + text,
                                      font: NSFont.systemFont(ofSize: 11),
                                      color: .secondaryLabelColor))
            }
        }

        if let code = result?.errorCode {
            let message = L.describe(code: code, detail: result?.errorDetail)
            menu.addItem(disabled("   ⚠︎ " + truncate(message, 52),
                                  font: NSFont.systemFont(ofSize: 11),
                                  color: .systemOrange))
        }

        // Kept numbers from an earlier success: say how old they are, because
        // the rows above look exactly like a live reading.
        if let usage = result?.usage, usage.isStale(limit: context.settings.staleAfter) {
            let age = L.t("menu.dataAge", Format.elapsed(since: usage.fetchedAt))
            menu.addItem(disabled("   " + age,
                                  font: NSFont.systemFont(ofSize: 11),
                                  color: .systemOrange))
        }

        menu.addItem(.separator())
    }

    /// One window row: `  5h    ██████░░░░  42%  2h13m后重置`
    private static func row(window: QuotaWindow,
                            font: NSFont,
                            settings: AppSettings,
                            label: String? = nil) -> NSMenuItem {
        let name = label ?? window.kind.shortLabel
        // Text and bar follow the "show remaining" setting like the menu bar
        // title does; the colour always tracks consumption.
        let value = settings.showRemaining ? window.remainingPercent : window.usedPercent
        let percent = Format.percent(value)
        let bar = Format.bar(value, width: 10)
        let reset = window.resetsAt.map { L.t("menu.windowReset", Format.countdown(to: $0)) } ?? ""

        let text = "   " + pad(name, 5) + " " + bar + "  " + padLeft(percent, 4) + "  " + reset
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: severityColor(window.usedPercent, settings: settings)
        ])
        return item
    }

    private static func needsCredentialHelp(_ context: Context) -> Bool {
        Service.allCases.contains { service in
            guard context.settings.isVisible(service) else { return false }
            let code = context.snapshot.result(for: service)?.errorCode
            return code == "credentials_missing" || code == "credentials_expired"
        }
    }

    private static func severityColor(_ used: Double, settings: AppSettings) -> NSColor {
        if used >= settings.dangerThreshold { return .systemRed }
        if used >= settings.warnThreshold { return .systemOrange }
        return .labelColor
    }

    // MARK: - Item helpers

    private static func disabled(_ text: String,
                                 font: NSFont,
                                 color: NSColor) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        return item
    }

    private static func action(title: String,
                               key: String,
                               enabled: Bool = true,
                               checked: Bool = false,
                               handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = .command
        item.isEnabled = enabled
        item.state = checked ? .on : .off
        return item
    }

    /// Pads with spaces to a fixed display width (CJK characters count as one
    /// cell here; service labels are ASCII so this is exact in practice).
    static func pad(_ text: String, _ width: Int) -> String {
        let missing = max(0, width - text.count)
        return text + String(repeating: " ", count: missing)
    }

    static func padLeft(_ text: String, _ width: Int) -> String {
        let missing = max(0, width - text.count)
        return String(repeating: " ", count: missing) + text
    }

    /// Truncates on character boundaries and appends an ellipsis.
    static func truncate(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit - 1))) + "…"
    }
}

/// `NSMenuItem` subclass that runs a closure. Avoids `@objc` selector plumbing
/// and lets the app keep all behaviour in one file.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        self.target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}
