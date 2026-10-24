import AppKit
import UsageBarCore

/// Owns the app lifecycle: state, timer, menu wiring and the settings window.
///
/// Threading: the class is `@MainActor` (AppKit requires it). Network work lives
/// in the `UsageService` actor and is awaited from here, so the main thread never
/// blocks even when a proxy is slow.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private var settings: AppSettings
    private var snapshot = UsageSnapshot(updatedAt: .distantPast)
    private let service: UsageService

    private var statusController: StatusItemController!
    private var timer: Timer?
    private var isRefreshing = false
    private var settingsWindow: SettingsWindowController?
    private var settingsModel: SettingsModel?

    override init() {
        let loaded = SettingsStore().load()
        settings = loaded
        service = UsageService(settings: loaded)
        super.init()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.trimIfNeeded()
        Log.debug("launch: version \(AppDelegate.version), settings \(AppPaths.settingsFile.path)")

        statusController = StatusItemController(fontSize: settings.fontSize)
        statusController.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        render()

        observeWake()
        scheduleTimer()

        Task { await bootstrap() }
    }

    /// Paints the cached snapshot first (instant numbers), then refreshes.
    private func bootstrap() async {
        snapshot = await service.cachedSnapshot()
        Log.debug("bootstrap: cached \(snapshot.results.count) result(s), updated \(snapshot.updatedAt)")
        render()
        await refresh(force: true)
    }

    // MARK: - Refresh

    private func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        render()

        snapshot = await service.refresh(force: force)
        Log.debug("refresh done: " + snapshot.results.map { key, value in
            "\(key.rawValue)=\(value.usage.map { "\(Int($0.maxUsedPercent))%" } ?? value.errorCode ?? "nil")"
        }.sorted().joined(separator: " "))

        isRefreshing = false
        render()
        // Restart the countdown from the moment the fetch finished, so the next
        // tick is a full interval away even if this one was slow.
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let tick = Timer(timeInterval: TimeInterval(settings.refreshIntervalSeconds),
                         repeats: true) { [weak self] _ in
            // Strong local binding: a `weak self` optional cannot be captured by
            // the sending Task closure (Swift 6 rejects it as a captured var).
            guard let self else { return }
            Task { @MainActor in
                await self.refresh(force: false)
            }
        }
        // `.common` keeps the timer alive while a menu is tracking, which is
        // exactly when a user is most likely to notice stale numbers.
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// Refresh immediately after the machine wakes: the cached numbers are
    /// usually hours old by then.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh(force: true)
            }
        }
    }

    // MARK: - Rendering

    private func render() {
        statusController.render(snapshot: snapshot,
                                settings: settings,
                                isRefreshing: isRefreshing)
    }

    private func makeMenu() -> NSMenu {
        // Opening the menu is a good moment to refresh if the data has aged past
        // one interval; it keeps the numbers honest without extra polling.
        let age = Date().timeIntervalSince(snapshot.updatedAt)
        if !isRefreshing, age > TimeInterval(settings.refreshIntervalSeconds) {
            Task { @MainActor in await self.refresh(force: false) }
        }

        return MenuBuilder.build(.init(
            snapshot: snapshot,
            settings: settings,
            isRefreshing: isRefreshing,
            launchAtLogin: LaunchAtLogin.isEnabled,
            onRefresh: { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.refresh(force: true) }
            },
            onSettings: { [weak self] in self?.showSettings() },
            onToggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            onOpenFolder: { AppPaths.reveal() },
            onOpenSetup: { Links.open(Links.setup) },
            onQuit: { NSApp.terminate(nil) }
        ))
    }

    // MARK: - Settings

    private func showSettings() {
        if settingsModel == nil {
            let model = SettingsModel(settings: settings) { [weak self] updated in
                self?.apply(updated)
            }
            settingsModel = model
            settingsWindow = SettingsWindowController(
                model: model,
                version: AppDelegate.version,
                onRefresh: { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in await self.refresh(force: true) }
                },
                onOpenFolder: { AppPaths.reveal() }
            )
        }
        settingsWindow?.present()
    }

    /// Persists and applies a settings change coming from the settings window.
    private func apply(_ updated: AppSettings) {
        settings = updated
        try? store.save(updated)
        statusController.apply(fontSize: settings.fontSize)
        render()

        Task {
            await service.apply(updated)
            await refresh(force: true)
        }
        scheduleTimer()
    }

    private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.toggle()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Misc

    /// Version string shown in the settings window and the CLI.
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}
