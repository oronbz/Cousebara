import Foundation

// MARK: - Copilot API Response Models

struct CopilotUserResponse: Decodable, Equatable, Sendable {
    let login: String?
    let copilotPlan: String?
    let quotaResetDate: String?
    let quotaSnapshots: QuotaSnapshots?

    enum CodingKeys: String, CodingKey {
        case login
        case copilotPlan = "copilot_plan"
        case quotaResetDate = "quota_reset_date"
        case quotaSnapshots = "quota_snapshots"
    }
}

struct QuotaSnapshots: Decodable, Equatable, Sendable {
    let premiumInteractions: QuotaSnapshot?

    enum CodingKeys: String, CodingKey {
        case premiumInteractions = "premium_interactions"
    }
}

struct QuotaSnapshot: Decodable, Equatable, Sendable {
    let entitlement: Int
    let overageCount: Int
    let overagePermitted: Bool
    let percentRemaining: Double
    let quotaRemaining: Double
    let remaining: Int
    let unlimited: Bool

    enum CodingKeys: String, CodingKey {
        case entitlement
        case overageCount = "overage_count"
        case overagePermitted = "overage_permitted"
        case percentRemaining = "percent_remaining"
        case quotaRemaining = "quota_remaining"
        case remaining
        case unlimited
    }

    init(
        entitlement: Int,
        overageCount: Int = 0,
        overagePermitted: Bool = true,
        percentRemaining: Double,
        quotaRemaining: Double,
        remaining: Int,
        unlimited: Bool = false
    ) {
        self.entitlement = entitlement
        self.overageCount = overageCount
        self.overagePermitted = overagePermitted
        self.percentRemaining = percentRemaining
        self.quotaRemaining = quotaRemaining
        self.remaining = remaining
        self.unlimited = unlimited
    }

    var used: Int {
        entitlement - remaining
    }

    var percentUsed: Double {
        guard entitlement > 0 else { return 0 }
        return 100.0 - percentRemaining
    }

    var isOverLimit: Bool {
        remaining < 0
    }

    var overageAmount: Int {
        max(0, -remaining)
    }

    /// Fraction used capped at 1.0 for the "normal" portion of the bar
    var normalFraction: Double {
        guard entitlement > 0 else { return 0 }
        return min(1.0, Double(used) / Double(entitlement))
    }

    /// Fraction of overshoot beyond 100% (e.g. 0.54 means 54% overshoot)
    var overageFraction: Double {
        guard entitlement > 0, isOverLimit else { return 0 }
        return Double(overageAmount) / Double(entitlement)
    }
}

// MARK: - Copilot Token

struct CopilotApp: Decodable, Sendable {
    let oauthToken: String

    enum CodingKeys: String, CodingKey {
        case oauthToken = "oauth_token"
    }
}

// MARK: - Copilot Errors

enum CopilotError: LocalizedError, Equatable {
    case noToken
    case tokenFileMissing
    case authenticationFailed
    case invalidURL
    case apiError

    var errorDescription: String? {
        switch self {
        case .noToken: "No Copilot OAuth token found in ~/.config/github-copilot/apps.json"
        case .tokenFileMissing: "GitHub Copilot token file not found. Sign in to create it."
        case .authenticationFailed: "Authentication failed. Your token may be expired or revoked."
        case .invalidURL: "Invalid API URL"
        case .apiError: "GitHub API request failed"
        }
    }

    /// Whether this error indicates the user needs to (re-)authenticate.
    var isAuthError: Bool {
        switch self {
        case .tokenFileMissing, .noToken, .authenticationFailed: true
        case .invalidURL, .apiError: false
        }
    }
}

// MARK: - Device Flow Response Models

struct DeviceCodeResponse: Decodable, Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct AccessTokenResponse: Decodable, Equatable, Sendable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
    }
}

// MARK: - Auth Phase

enum AuthPhase: Equatable, Sendable {
    case idle
    case awaitingUser(code: String, verificationURL: String)
    case success
    case error(String)
}

// MARK: - Auth Errors

enum AuthError: LocalizedError, Equatable {
    case deviceCodeRequestFailed
    case expired
    case accessDenied
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .deviceCodeRequestFailed:
            "Failed to start GitHub authentication."
        case .expired:
            "Authentication timed out. Please try again."
        case .accessDenied:
            "Access was denied. Please try again and approve the request."
        case .networkError(let message):
            "Network error: \(message)"
        }
    }
}

// MARK: - Preview Mock Data

extension QuotaSnapshot {
    /// Low usage: 30% used (300 / 1000)
    static let lowUsage = QuotaSnapshot(
        entitlement: 1000,
        percentRemaining: 70.0,
        quotaRemaining: 700.0,
        remaining: 700
    )

    /// Medium usage: 65% used (650 / 1000)
    static let mediumUsage = QuotaSnapshot(
        entitlement: 1000,
        percentRemaining: 35.0,
        quotaRemaining: 350.0,
        remaining: 350
    )

    /// High usage: 90% used (900 / 1000)
    static let highUsage = QuotaSnapshot(
        entitlement: 1000,
        percentRemaining: 10.0,
        quotaRemaining: 100.0,
        remaining: 100
    )

    /// At limit: 100% used (1000 / 1000)
    static let atLimit = QuotaSnapshot(
        entitlement: 1000,
        percentRemaining: 0.0,
        quotaRemaining: 0.0,
        remaining: 0
    )

    /// Over limit: 154% used (1540 / 1000), matching real API negative values
    static let overLimit = QuotaSnapshot(
        entitlement: 1000,
        overageCount: 540,
        percentRemaining: -54.099,
        quotaRemaining: -540.99,
        remaining: -540
    )

    /// Slightly over: 110% used (1100 / 1000)
    static let slightlyOver = QuotaSnapshot(
        entitlement: 1000,
        overageCount: 100,
        percentRemaining: -10.0,
        quotaRemaining: -100.0,
        remaining: -100
    )
}
