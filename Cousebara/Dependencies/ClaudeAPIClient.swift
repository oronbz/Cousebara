import Dependencies
import DependenciesMacros
import Foundation
import Security

@DependencyClient
struct ClaudeAPIClient: Sendable {
    var readToken: @Sendable () throws -> String
    var fetchUsage: @Sendable (_ token: String) async throws -> ClaudeUsage
    var fetchProfile: @Sendable (_ token: String) async throws -> ClaudeProfile
}

extension ClaudeAPIClient: TestDependencyKey {
    static var previewValue: ClaudeAPIClient {
        ClaudeAPIClient(
            readToken: { "preview-token" },
            fetchUsage: { _ in
                ClaudeUsage(
                    session: UsageWindow(
                        utilization: 35,
                        resetsAt: Date().addingTimeInterval(2 * 60 * 60),
                        length: UsageWindow.sessionLength
                    ),
                    weekly: UsageWindow(
                        utilization: 62,
                        resetsAt: Date().addingTimeInterval(4 * 24 * 60 * 60),
                        length: UsageWindow.weeklyLength
                    )
                )
            },
            fetchProfile: { _ in
                ClaudeProfile(
                    displayName: "Preview User",
                    email: "preview@example.com",
                    orgName: "Preview Org",
                    planLabel: "Max 5X"
                )
            }
        )
    }
}

extension ClaudeAPIClient: DependencyKey {
    static var liveValue: ClaudeAPIClient {
        ClaudeAPIClient(
            readToken: {
                let data = try readKeychainCredentials()
                let creds = try JSONDecoder().decode(ClaudeCredentials.self, from: data)
                if let expiresAt = creds.claudeAiOauth.expiresAt {
                    let nowMs = Date().timeIntervalSince1970 * 1000
                    if expiresAt <= nowMs { throw ClaudeError.tokenExpired }
                }
                return creds.claudeAiOauth.accessToken
            },
            fetchUsage: { token in
                let url = try claudeURL("https://api.anthropic.com/api/oauth/usage")
                let (data, response) = try await authedGet(url, token: token)
                try validate(response)
                let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
                return ClaudeUsage(response: decoded)
            },
            fetchProfile: { token in
                let url = try claudeURL("https://api.anthropic.com/api/oauth/profile")
                let (data, response) = try await authedGet(url, token: token)
                try validate(response)
                let decoded = try JSONDecoder().decode(ClaudeProfileResponse.self, from: data)
                return ClaudeProfile(response: decoded)
            }
        )
    }
}

// MARK: - Keychain

private struct ClaudeCredentials: Decodable {
    struct OAuth: Decodable {
        let accessToken: String
        let expiresAt: Double?

        // Keys confirmed via live smoke test (camelCase, not snake_case).
        enum CodingKeys: String, CodingKey {
            case accessToken
            case expiresAt
        }
    }
    let claudeAiOauth: OAuth

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth
    }
}

private func readKeychainCredentials() throws -> Data {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
        guard let data = item as? Data else { throw ClaudeError.noToken }
        return data
    case errSecItemNotFound:
        throw ClaudeError.noToken
    case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
        throw ClaudeError.keychainDenied
    default:
        throw ClaudeError.keychainDenied
    }
}

// MARK: - HTTP

/// The Claude usage endpoint aggressively rate-limits requests that don't
/// identify as Claude Code. Sending this User-Agent uses the same, far more
/// generous bucket the CLI gets. Bump this to match the installed CLI version.
private let claudeCodeUserAgent = "claude-code/2.1.159"

private func claudeURL(_ string: String) throws -> URL {
    guard let url = URL(string: string) else { throw ClaudeError.invalidURL }
    return url
}

private func authedGet(_ url: URL, token: String) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(claudeCodeUserAgent, forHTTPHeaderField: "User-Agent")
    return try await URLSession.shared.data(for: request)
}

private func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw ClaudeError.apiError }
    if http.statusCode == 401 || http.statusCode == 403 {
        throw ClaudeError.authenticationFailed
    }
    guard http.statusCode == 200 else { throw ClaudeError.apiError }
}
