import Foundation

// MARK: - ISO8601 Parsing

/// Parses the ISO-8601 timestamps returned by the Claude usage API, which
/// include 6-digit fractional seconds and a colon-separated offset
/// (e.g. "2026-06-01T10:00:00.049345+00:00"). Fractional seconds are stripped
/// for robustness, then parsed with the default internet-date-time format.
enum ISO8601 {
    private static let formatter = ISO8601DateFormatter()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        let stripped = string.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )
        return formatter.date(from: stripped)
    }
}

// MARK: - Usage Window

enum UsageLevel: Equatable, Sendable {
    case normal   // < 60%
    case warning  // 60–85%
    case high     // 85–100%
    case maxed    // >= 100%
}

struct UsageWindow: Equatable, Sendable {
    let utilization: Double   // 0–100
    let resetsAt: Date?
    let length: TimeInterval

    static let sessionLength: TimeInterval = 5 * 60 * 60
    static let weeklyLength: TimeInterval = 7 * 24 * 60 * 60

    var percentUsed: Double { utilization }
    var percentRemaining: Double { max(0, 100 - utilization) }
    var fraction: Double { min(1, max(0, utilization / 100)) }
    var remainingFraction: Double { max(0, 1 - fraction) }
    var isMaxed: Bool { utilization >= 100 }

    var level: UsageLevel {
        if utilization >= 100 { return .maxed }
        if utilization >= 85 { return .high }
        if utilization >= 60 { return .warning }
        return .normal
    }

    func paceReserve(now: Date) -> PaceReserve? {
        guard let resetsAt else { return nil }
        let start = resetsAt.addingTimeInterval(-length)
        return PaceReserve.calculate(
            percentUsed: utilization,
            windowStart: start,
            windowEnd: resetsAt,
            now: now
        )
    }
}

// MARK: - Generalized Pace

extension PaceReserve {
    /// Pace over an arbitrary window defined by an explicit start and end.
    static func calculate(
        percentUsed: Double,
        windowStart: Date,
        windowEnd: Date,
        now: Date
    ) -> PaceReserve? {
        let total = windowEnd.timeIntervalSince(windowStart)
        guard total > 0 else { return nil }
        let elapsed = now.timeIntervalSince(windowStart)
        let percentTimeElapsed = min(max(elapsed / total * 100, 0), 100)
        return PaceReserve(
            percentTimeElapsed: percentTimeElapsed,
            reserve: percentTimeElapsed - percentUsed
        )
    }
}

// MARK: - Usage API Models

struct ClaudeUsageResponse: Decodable, Equatable, Sendable {
    struct Window: Decodable, Equatable, Sendable {
        let utilization: Double
        let resetsAtRaw: String?
        var resetsAt: Date? { ISO8601.date(from: resetsAtRaw) }

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAtRaw = "resets_at"
        }
    }

    let fiveHour: Window?
    let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct ClaudeUsage: Equatable, Sendable {
    let session: UsageWindow
    let weekly: UsageWindow

    init(session: UsageWindow, weekly: UsageWindow) {
        self.session = session
        self.weekly = weekly
    }

    init(response: ClaudeUsageResponse) {
        session = UsageWindow(
            utilization: response.fiveHour?.utilization ?? 0,
            resetsAt: response.fiveHour?.resetsAt,
            length: UsageWindow.sessionLength
        )
        weekly = UsageWindow(
            utilization: response.sevenDay?.utilization ?? 0,
            resetsAt: response.sevenDay?.resetsAt,
            length: UsageWindow.weeklyLength
        )
    }
}

// MARK: - Profile API Models

struct ClaudeProfileResponse: Decodable, Equatable, Sendable {
    struct Account: Decodable, Equatable, Sendable {
        let displayName: String?
        let email: String?
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case email
        }
    }

    struct Organization: Decodable, Equatable, Sendable {
        let name: String?
        let rateLimitTier: String?
        enum CodingKeys: String, CodingKey {
            case name
            case rateLimitTier = "rate_limit_tier"
        }
    }

    let account: Account?
    let organization: Organization?
}

struct ClaudeProfile: Equatable, Sendable {
    let displayName: String?
    let email: String?
    let orgName: String?
    let planLabel: String?

    init(displayName: String?, email: String?, orgName: String?, planLabel: String?) {
        self.displayName = displayName
        self.email = email
        self.orgName = orgName
        self.planLabel = planLabel
    }

    init(response: ClaudeProfileResponse) {
        displayName = response.account?.displayName
        email = response.account?.email
        orgName = response.organization?.name
        planLabel = ClaudeProfile.humanizeTier(response.organization?.rateLimitTier)
    }

    /// "default_claude_max_5x" → "Max 5x" (deterministic; avoids locale-specific .capitalized)
    static func humanizeTier(_ tier: String?) -> String? {
        guard let tier else { return nil }
        let cleaned = tier
            .replacingOccurrences(of: "default_", with: "")
            .replacingOccurrences(of: "claude_", with: "")
        let words = cleaned.split(separator: "_").map { word -> String in
            guard let first = word.first else { return String(word) }
            return first.uppercased() + word.dropFirst()
        }
        let result = words.joined(separator: " ")
        return result.isEmpty ? nil : result
    }
}

// MARK: - Claude Errors

enum ClaudeError: LocalizedError, Equatable {
    case noToken
    case keychainDenied
    case tokenExpired
    case authenticationFailed
    case invalidURL
    case apiError

    var errorDescription: String? {
        switch self {
        case .noToken:
            "No Claude credentials found. Log in with Claude Code first."
        case .keychainDenied:
            "Keychain access was denied. Allow Cousebara to read the Claude credentials."
        case .tokenExpired:
            "Your Claude session token expired. Open Claude Code to refresh it."
        case .authenticationFailed:
            "Authentication failed. Your Claude token may be expired or revoked."
        case .invalidURL:
            "Invalid API URL."
        case .apiError:
            "Claude usage request failed."
        }
    }

    var isAuthError: Bool {
        switch self {
        case .noToken, .keychainDenied, .tokenExpired, .authenticationFailed: true
        case .invalidURL, .apiError: false
        }
    }
}
