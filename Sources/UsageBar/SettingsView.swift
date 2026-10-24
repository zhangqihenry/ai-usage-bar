import AppKit
import SwiftUI
import UsageBarCore

/// Mutable bridge between the SwiftUI settings form and the AppKit delegate.
///
/// Every edit is normalised and forwarded immediately, so there is no "Apply"
/// button and the menu bar updates while the user drags a control.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard !isSilentUpdate else { return }
            onChange(settings.normalized())
        }
    }

    /// Called on every user edit with the normalised settings.
    var onChange: (AppSettings) -> Void

    private var isSilentUpdate = false

    init(settings: AppSettings, onChange: @escaping (AppSettings) -> Void = { _ in }) {
        self.settings = settings
        self.onChange = onChange
    }

    func resetToDefaults() {
        isSilentUpdate = true
        settings = AppSettings()
        isSilentUpdate = false
        onChange(settings)
    }
}

/// The settings window content. Deliberately plain SwiftUI `Form`: it adapts to
/// light/dark automatically and needs no custom drawing.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var version: String
    var onRefresh: () -> Void
    var onOpenFolder: () -> Void

    /// Intervals offered in the picker, in seconds.
    private let intervals = [60, 120, 300, 600, 900, 1800]

    var body: some View {
        Form {
            Section {
                Picker(L.t("settings.refreshInterval"), selection: $model.settings.refreshIntervalSeconds) {
                    ForEach(intervals, id: \.self) { seconds in
                        Text(L.t("settings.minutes", seconds / 60)).tag(seconds)
                    }
                }
                Picker(L.t("settings.displayMode"), selection: $model.settings.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker(L.t("settings.titleStyle"), selection: $model.settings.titleStyle) {
                    Text("12/48").tag(TitleStyle.compact)
                    Text("12% / 48%").tag(TitleStyle.labeled)
                }
                Toggle(L.t("settings.showRemaining"), isOn: $model.settings.showRemaining)
            } header: {
                Text(L.t("settings.general"))
            }

            Section {
                Toggle(Service.codex.displayName, isOn: $model.settings.showCodex)
                Toggle(Service.claude.displayName, isOn: $model.settings.showClaude)
            } header: {
                Text(L.t("settings.services"))
            }

            Section {
                Picker(L.t("settings.proxyMode"), selection: $model.settings.proxy.mode) {
                    Text("System").tag(ProxyConfiguration.Mode.system)
                    Text("Direct").tag(ProxyConfiguration.Mode.direct)
                    Text("Manual").tag(ProxyConfiguration.Mode.manual)
                }
                if model.settings.proxy.mode == .manual {
                    Picker(L.t("settings.proxyScheme"), selection: $model.settings.proxy.scheme) {
                        Text("HTTP").tag(ProxyConfiguration.Scheme.http)
                        Text("SOCKS5").tag(ProxyConfiguration.Scheme.socks5)
                    }
                    TextField(L.t("settings.proxyHost"), text: $model.settings.proxy.host)
                    TextField(L.t("settings.proxyPort"),
                              value: $model.settings.proxy.port,
                              format: .number)
                }
                Text(L.t("settings.proxyHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L.t("settings.proxy"))
            }

            Section {
                HStack(spacing: 10) {
                    Button(L.t("settings.refresh"), action: onRefresh)
                    Button(L.t("settings.openFolder"), action: onOpenFolder)
                    Button(L.t("settings.reset")) { model.resetToDefaults() }
                    Spacer()
                    Text(L.t("settings.version", version))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(L.t("settings.footnote", AppPaths.settingsFile.path))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hosts `SettingsView` in a normal window and keeps it alive between openings.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: SettingsModel,
         version: String,
         onRefresh: @escaping () -> Void,
         onOpenFolder: @escaping () -> Void) {
        let view = SettingsView(model: model,
                                version: version,
                                onRefresh: onRefresh,
                                onOpenFolder: onOpenFolder)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = L.t("settings.title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
