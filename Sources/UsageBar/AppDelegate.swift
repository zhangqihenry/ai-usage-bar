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
    /// Debounced refresh after a network relevant settings edit.
    private var pendingSettingsRefresh: Task<Void, Never>?
    /// Quick retry while a service reports a transport error.
    private var networkRetry: Task<Void, Never>?
    private var networkRetryCount = 0
    private let notifier = Notifier()

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
        LaunchAtLogin.repairIfNeeded()
        if settings.notifyOnThresholds { notifier.requestPermission() }

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

        // Hand over the current settings first, so a refresh never runs with a
        // proxy or service selection the user has already changed.
        await service.apply(settings)
        snapshot = await service.refresh(force: force)
        Log.debug("refresh done: " + snapshot.results.map { key, value in
            "\(key.rawValue)=\(value.usage.map { "\(Int($0.maxUsedPercent))%" } ?? value.errorCode ?? "nil")"
        }.sorted().joined(separator: " "))

        isRefreshing = false
        render()
        notifier.process(snapshot, settings: settings)
        // Restart the countdown from the moment the fetch finished, so the next
        // tick is a full interval away even if this one was slow.
        scheduleTimer()
        scheduleNetworkRetryIfNeeded()
    }

    /// A transport error (offline, proxy not up yet) costs no vendor quota, so
    /// it is retried well before the next tick: 30 s, 60 s, 120 s ... capped at
    /// the polling interval.
    private func scheduleNetworkRetryIfNeeded() {
        networkRetry?.cancel()
        let failing = Service.allCases.contains { service in
            isVisible(service) && snapshot.result(for: service)?.errorCode == UsageError.network("").code
        }
        guard failing else {
            networkRetryCount = 0
            return
        }
        let delay = min(Double(settings.refreshIntervalSeconds), 30 * pow(2, Double(networkRetryCount)))
        networkRetryCount += 1
        Log.debug("network error: retry in \(Int(delay))s")
        networkRetry = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.refresh(force: false)
        }
    }

    private func isVisible(_ service: Service) -> Bool {
        service == .codex ? settings.showCodex : settings.showClaude
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

    /// Refresh shortly after the machine wakes: the cached numbers are usually
    /// hours old by then. The short delay gives Wi-Fi and a local proxy time to
    /// come back; if they are still down, the network retry takes over.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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
    ///
    /// The settings window reports every keystroke, so this must stay cheap:
    /// display-only edits (style, thresholds, remaining/used) just re-render.
    /// Only a proxy change or a newly enabled service needs the network, and that
    /// refresh is debounced so typing a proxy host costs one request, not one per
    /// character.
    private func apply(_ updated: AppSettings) {
        let previous = settings
        settings = updated
        try? store.save(updated)
        statusController.apply(fontSize: settings.fontSize)
        render()

        if updated.refreshIntervalSeconds != previous.refreshIntervalSeconds {
            scheduleTimer()
        }
        if updated.notifyOnThresholds, !previous.notifyOnThresholds {
            notifier.requestPermission()
        }

        let proxyChanged = updated.proxy != previous.proxy
        let serviceEnabled = (updated.showCodex && !previous.showCodex)
            || (updated.showClaude && !previous.showClaude)
        guard proxyChanged || serviceEnabled else { return }

        pendingSettingsRefresh?.cancel()
        pendingSettingsRefresh = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            // A new proxy deserves an immediate retry (it is usually the fix for
            // a 403); a re-enabled service still respects its minimum interval.
            await self.refresh(force: proxyChanged)
        }
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
