import Foundation

/// Minimal, signature-less JWT payload decoder.
///
/// This is **not** used for any security decision. It exists only so the UI can
/// show "token expires in 3 days" style diagnostics and the account e-mail
/// without asking the user. Signature verification would be pointless here: the
/// token is handed to us by the provider's own CLI and we never mint tokens.
public enum JWT {
    /// Returns the decoded payload dictionary, or nil when the string is not a
    /// JWT at all (e.g. an opaque API key).
    public static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        // JWT uses base64url without padding; Data(base64Encoded:) needs both.
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64) else { return nil }
        let object = try? JSONSerialization.jsonObject(with: data)
        return object as? [String: Any]
    }

    /// `exp` claim as a Date.
    public static func expiry(of token: String) -> Date? {
        guard let exp = payload(of: token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// E-mail claim. OpenAI puts it in the namespaced `https://api.openai.com/profile`
    /// object; Anthropic puts it at the top level. Both shapes are handled.
    public static func email(of token: String) -> String? {
        guard let payload = payload(of: token) else { return nil }
        if let email = payload["email"] as? String { return email }
        if let profile = payload["https://api.openai.com/profile"] as? [String: Any],
           let email = profile["email"] as? String {
            return email
        }
        return nil
    }
}
