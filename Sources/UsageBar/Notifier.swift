import AppKit
import UserNotifications
import UsageBarCore

/// Posts threshold alerts as macOS notifications.
///
/// `ThresholdTracker` (Core) decides *when*; this type only asks for permission
/// and delivers. UserNotifications needs a real app bundle, so outside
/// `UsageBar.app` (e.g. `swift run usagebar`) every call is a no-op instead of a
/// crash.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var tracker = ThresholdTracker()

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Called when the user turns alerts on, and at launch when they already
    /// are. macOS shows its permission prompt only the first time.
    func requestPermission() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Log.debug("notifications: granted=\(granted) error=\(error?.localizedDescription ?? "nil")")
        }
    }

    /// Feeds every refreshed snapshot through the tracker, so levels stay
    /// current even while alerts are off; posts only when they are on.
    func process(_ snapshot: UsageSnapshot, settings: AppSettings) {
        let alerts = tracker.alerts(for: snapshot, settings: settings)
        guard settings.notifyOnThresholds, let center else { return }

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = L.t("notify.title",
                                alert.service.displayName,
                                alert.kind.shortLabel,
                                Format.percent(alert.usedPercent))
            content.body = alert.resetsAt.map { L.t("notify.reset", Format.countdown(to: $0)) }
                ?? L.t("notify.noReset")
            if alert.level == .danger { content.sound = .default }

            // One identifier per window and level: a repeat replaces the old
            // banner in Notification Center instead of stacking up.
            let identifier = "\(alert.service.rawValue).\(alert.kind.rawValue).\(alert.level.rawValue)"
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            Log.debug("notify: \(identifier) \(Int(alert.usedPercent))%")
        }
    }

    /// A menu bar app counts as frontmost while its settings window is open;
    /// show the banner anyway instead of swallowing it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                            @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
