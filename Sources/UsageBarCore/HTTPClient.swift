import Foundation

/// A decoded HTTP response. Kept small on purpose: the providers only need the
/// body and the status code.
public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let url: URL?
}

/// All network traffic goes through this one client so proxy handling lives in
/// exactly one place.
public final class HTTPClient: @unchecked Sendable {
    public let proxy: ProxyConfiguration
    private let session: URLSession

    /// - Parameter timeout: per-request timeout. 25 s is generous enough for a
    ///   slow proxy hop and short enough that a stalled refresh does not wedge
    ///   the UI (the refresh runs off the main thread anyway).
    public init(proxy: ProxyConfiguration, timeout: TimeInterval = 25) {
        self.proxy = proxy

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        // nil => CFNetwork follows the macOS system proxy settings.
        configuration.connectionProxyDictionary = proxy.connectionProxyDictionary

        self.session = URLSession(configuration: configuration)
    }

    /// Performs a GET and returns the raw body, translating HTTP failures into
    /// `UsageError` so callers never have to look at status codes.
    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw UsageError.network(Self.describe(error))
        } catch {
            throw UsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("Not an HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            return HTTPResponse(data: data, status: http.statusCode, url: http.url)
        case 401:
            throw UsageError.unauthorized
        case 403:
            // chatgpt.com answers 403 with an HTML page for blocked regions and
            // for tunnel traffic it dislikes. Both look identical from here.
            throw UsageError.blocked
        case 429:
            throw UsageError.rateLimited
        default:
            throw UsageError.http(http.statusCode)
        }
    }

    /// Fetches and decodes JSON. The generic helper keeps the providers free of
    /// `JSONDecoder` boilerplate.
    public func getJSON<T: Decodable>(_ type: T.Type,
                                      from url: URL,
                                      headers: [String: String],
                                      decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let response = try await get(url, headers: headers)
        do {
            return try decoder.decode(T.self, from: response.data)
        } catch {
            let snippet = Self.plainText(from: response.data, limit: 160)
            throw UsageError.decoding("Unexpected JSON (\(snippet))")
        }
    }

    // MARK: - Helpers

    /// Turns URLError codes into sentences a user can act on.
    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "No internet connection"
        case .timedOut: return "Request timed out"
        case .cannotFindHost, .dnsLookupFailed: return "DNS lookup failed"
        case .cannotConnectToHost: return "Cannot connect to host (proxy down?)"
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return "TLS handshake failed (captive portal or proxy interception?)"
        case .userAuthenticationRequired: return "Proxy authentication required"
        default: return error.localizedDescription
        }
    }

    /// Strips HTML tags so an error message can quote the server's own words
    /// without dumping a whole Cloudflare page into the menu.
    static func plainText(from data: Data, limit: Int) -> String {
        let raw = String(decoding: data, as: UTF8.self)
        let withoutTags = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let cleaned = withoutTags
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(limit))
    }
}

/// Thin ISO-8601 parsing helper. Anthropic sends `2026-04-21T03:00:00.000+00:00`
/// (fractional seconds, numeric offset); Codex sends unix timestamps. Both are
/// normalised to `Date` here.
enum ISO8601 {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return withFractionalSeconds.date(from: string) ?? plain.date(from: string)
    }
}
