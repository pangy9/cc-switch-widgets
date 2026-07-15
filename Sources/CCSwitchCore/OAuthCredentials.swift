import Foundation

/// OAuth 凭据读取结果。
public struct OAuthCredential: Sendable {
    public let token: String?
    public let accountId: String?
    public let status: CredentialStatus
    public let message: String?

    public init(token: String?, accountId: String?, status: CredentialStatus, message: String?) {
        self.token = token
        self.accountId = accountId
        self.status = status
        self.message = message
    }
}

/// 从 ~/.claude/.credentials.json 和 ~/.codex/auth.json 读取 OAuth 凭据。
/// 照搬 cc-switch subscription.rs 的 read_claude_credentials_from_file / read_codex_credentials_from_file。
public enum OAuthCredentialReader {
    /// 读 Claude OAuth：~/.claude/.credentials.json 的 claudeAiOauth.accessToken（兼容 claude.ai_oauth）+ expiresAt 过期判断。
    public static func readClaude() -> OAuthCredential {
        let credPath = realHomeDirectory().appendingPathComponent(".claude/.credentials.json")
        guard FileManager.default.fileExists(atPath: credPath.path),
              let data = try? Data(contentsOf: credPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OAuthCredential(token: nil, accountId: nil, status: .notFound, message: "未找到 ~/.claude/.credentials.json")
        }
        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? (json["claude.ai_oauth"] as? [String: Any])
        guard let oauth, let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return OAuthCredential(token: nil, accountId: nil, status: .parseError, message: "凭据缺少 accessToken")
        }
        if let expiresAt = oauth["expiresAt"], isTokenExpired(expiresAt) {
            return OAuthCredential(token: token, accountId: nil, status: .expired, message: "Claude 凭据已过期，请用 Claude CLI 重新登录")
        }
        return OAuthCredential(token: token, accountId: nil, status: .valid, message: nil)
    }

    /// 读 Codex OAuth：~/.codex/auth.json（auth_mode=="chatgpt", tokens.access_token, tokens.account_id），last_refresh > 8 天 stale。
    public static func readCodex() -> OAuthCredential {
        let authPath = realHomeDirectory().appendingPathComponent(".codex/auth.json")
        guard FileManager.default.fileExists(atPath: authPath.path),
              let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OAuthCredential(token: nil, accountId: nil, status: .notFound, message: "未找到 ~/.codex/auth.json")
        }
        let authMode = (json["auth_mode"] as? String) ?? ""
        guard authMode == "chatgpt" else {
            return OAuthCredential(token: nil, accountId: nil, status: .notFound, message: "Codex 非 OAuth 模式（auth_mode != chatgpt）")
        }
        guard let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty else {
            return OAuthCredential(token: nil, accountId: nil, status: .parseError, message: "凭据缺少 access_token")
        }
        let accountId = tokens["account_id"] as? String

        if let lastRefresh = json["last_refresh"] as? String,
           let refreshDate = ISO8601DateFormatter().date(from: lastRefresh),
           Date().timeIntervalSince(refreshDate) > 8 * 86400 {
            return OAuthCredential(token: token, accountId: accountId, status: .expired, message: "Codex 凭据已过期（last_refresh > 8 天）")
        }
        return OAuthCredential(token: token, accountId: accountId, status: .valid, message: nil)
    }

    /// expiresAt 过期判断：兼容毫秒（>1e12）/秒/ISO 字符串（照搬 cc-switch subscription.rs L246-279）。
    private static func isTokenExpired(_ value: Any) -> Bool {
        if let n = value as? Double {
            let seconds = n > 1e12 ? n / 1000 : n
            return Date(timeIntervalSince1970: seconds) <= Date()
        }
        if let n = value as? Int {
            let seconds = Double(n) > 1e12 ? Double(n) / 1000 : Double(n)
            return Date(timeIntervalSince1970: seconds) <= Date()
        }
        if let s = value as? String, let date = ISO8601DateFormatter().date(from: s) {
            return date <= Date()
        }
        return false
    }
}
