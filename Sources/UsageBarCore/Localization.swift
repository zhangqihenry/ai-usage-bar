import Foundation

/// Bilingual strings. The app targets a Chinese speaking author but is meant to
/// be usable by anyone on GitHub, so the language follows the system preference
/// (Chinese → zh, everything else → en) instead of hard coding one.
///
/// Rules for contributors: never build a user visible sentence by
/// concatenating fragments, and always add both languages to the table below.
public enum L {
    public enum Language: String, Sendable {
        case zh
        case en
    }

    /// Resolved once at launch. `USAGEBAR_LANG=zh|en` forces a language, which is
    /// handy for screenshots and for tests.
    public static let language: Language = {
        if let forced = ProcessInfo.processInfo.environment["USAGEBAR_LANG"]?.lowercased(),
           forced == "zh" || forced == "en" {
            return forced == "zh" ? .zh : .en
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .zh : .en
    }()

    /// key: (Chinese, English)
    private static let table: [String: (zh: String, en: String)] = [
        // Menu bar / menu
        "menu.refresh": ("立即刷新", "Refresh Now"),
        "menu.refreshing": ("正在刷新…", "Refreshing…"),
        "menu.settings": ("设置…", "Settings…"),
        "menu.launchAtLogin": ("开机自动启动", "Launch at Login"),
        "menu.openFolder": ("打开配置文件夹", "Open Config Folder"),
        "menu.quit": ("退出", "Quit"),
        "menu.updated": ("更新于 %@", "Updated %@"),
        "menu.stale": ("更新于 %@（数据可能已过期）", "Updated %@ (stale)"),
        "menu.never": ("尚未获取数据", "No data yet"),
        "menu.windowReset": ("%@后重置", "resets in %@"),
        "menu.noWindow": ("无此窗口", "not on this plan"),
        "menu.plan": ("套餐 %@", "Plan %@"),
        "menu.proxy": ("代理 %@", "Proxy %@"),
        "menu.limitReached": ("已达上限", "limit reached"),
        "menu.loginHelp": ("如何登录并获取用量…", "How to get credentials…"),

        // Settings window
        "settings.title": ("用量栏设置", "Usage Bar Settings"),
        "settings.general": ("通用", "General"),
        "settings.refreshInterval": ("刷新间隔", "Refresh interval"),
        "settings.displayMode": ("菜单栏显示", "Menu bar shows"),
        "settings.titleStyle": ("数值样式", "Number style"),
        "settings.showRemaining": ("显示剩余量", "Show remaining instead of used"),
        "settings.services": ("服务", "Services"),
        "settings.proxy": ("网络 / 代理", "Network / Proxy"),
        "settings.proxyMode": ("模式", "Mode"),
        "settings.proxyHost": ("地址", "Host"),
        "settings.proxyPort": ("端口", "Port"),
        "settings.proxyScheme": ("协议", "Scheme"),
        "settings.proxyHint": ("ChatGPT 在部分地区会被拒绝访问。系统代理不行时，选「手动」并填入本地代理端口（Clash 默认 127.0.0.1:7897）。",
                               "ChatGPT refuses some regions. If the system proxy does not help, choose Manual and enter your local proxy port (Clash defaults to 127.0.0.1:7897)."),
        "settings.minutes": ("%d 分钟", "%d min"),
        "settings.footnote": ("配置文件：%@", "Config file: %@"),
        "settings.openFolder": ("打开文件夹", "Open folder"),
        "settings.refresh": ("立即刷新", "Refresh now"),
        "settings.reset": ("恢复默认", "Reset to defaults"),
        "settings.version": ("版本 %@", "Version %@"),

        // Errors
        "error.credentials_missing": ("未找到登录凭证，请先登录对应客户端。", "Credentials not found. Sign in with the vendor client first."),
        "error.credentials_expired": ("登录已过期，请重新打开对应客户端刷新登录。", "Session expired. Reopen the vendor client to refresh it."),
        "error.unauthorized": ("凭证被拒绝（401），请重新登录。", "Credentials rejected (401). Sign in again."),
        "error.blocked": ("请求被拒绝（403）。当前网络可能被屏蔽，请在设置里启用代理。", "Rejected (403). Your network may be blocked; enable a proxy in Settings."),
        "error.rate_limited": ("请求过于频繁（429），稍后会自动重试。", "Rate limited (429). A retry is scheduled."),
        "error.http": ("服务器返回 HTTP %@。", "Server returned HTTP %@."),
        "error.network": ("网络错误：%@", "Network error: %@"),
        "error.decoding": ("返回的数据无法解析。", "The response could not be parsed."),
        "error.unknown": ("未知错误。", "Unknown error.")
    ]

    public static func t(_ key: String) -> String {
        guard let entry = table[key] else { return key }
        return language == .zh ? entry.zh : entry.en
    }

    /// `String(format:)` with the language's table entry as the template.
    public static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    /// Renders a stored error code plus its technical detail into one sentence.
    public static func describe(code: String, detail: String?) -> String {
        let sentence: String
        switch code {
        case "credentials_missing": sentence = t("error.credentials_missing")
        case "credentials_expired": sentence = t("error.credentials_expired")
        case "unauthorized":        sentence = t("error.unauthorized")
        case "blocked":             sentence = t("error.blocked")
        case "rate_limited":        sentence = t("error.rate_limited")
        case "network":             sentence = detail ?? t("error.network", "")
        case "decoding":            sentence = t("error.decoding")
        case "unknown":             sentence = t("error.unknown")
        default:
            if code.hasPrefix("http_") {
                sentence = t("error.http", String(code.dropFirst(5)))
            } else {
                sentence = t("error.unknown")
            }
        }

        // Technical detail is shown in parentheses: it stays in English because
        // it comes from the vendor API and is aimed at bug reports.
        guard let detail, !detail.isEmpty, code != "network" else { return sentence }
        return "\(sentence) (\(detail))"
    }
}
