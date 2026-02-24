import Foundation

// MARK: - API Response Models

struct CopilotUserResponse: Decodable {
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

struct QuotaSnapshots: Decodable {
    let premiumInteractions: QuotaSnapshot?

    enum CodingKeys: String, CodingKey {
        case premiumInteractions = "premium_interactions"
    }
}

struct QuotaSnapshot: Decodable {
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

struct CopilotApp: Decodable {
    let oauthToken: String

    enum CodingKeys: String, CodingKey {
        case oauthToken = "oauth_token"
    }
}

// MARK: - Service

@Observable
final class CopilotService {
    var usage: QuotaSnapshot?
    var login: String?
    var plan: String?
    var resetDate: String?
    var lastUpdated: Date?
    var error: String?
    var isLoading = false
    /// True when authentication is needed (token file missing or API returned 401/403).
    var needsAuth = false

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 15 * 60 // 15 minutes
    private let skipNetwork: Bool

    init() {
        skipNetwork = false
        startAutoRefresh()
    }

    /// Preview-only initializer that populates state without network calls.
    init(
        usage: QuotaSnapshot?,
        login: String? = "oronbz",
        plan: String? = "enterprise",
        resetDate: String? = "2026-03-01",
        error: String? = nil,
        isLoading: Bool = false,
        needsAuth: Bool = false
    ) {
        self.skipNetwork = true
        self.usage = usage
        self.login = login
        self.plan = plan
        self.resetDate = resetDate
        self.error = error
        self.isLoading = isLoading
        self.needsAuth = needsAuth
        self.lastUpdated = Date()
    }

    func startAutoRefresh() {
        guard !skipNetwork else { return }

        // Initial fetch
        Task { await refresh() }

        // Set up recurring timer
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    func refresh() async {
        guard !skipNetwork else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let token = try readToken()
            let response = try await fetchUsage(token: token)
            usage = response.quotaSnapshots?.premiumInteractions
            login = response.login
            plan = response.copilotPlan
            resetDate = response.quotaResetDate
            lastUpdated = Date()
            error = nil
            needsAuth = false
        } catch let copilotError as CopilotError where copilotError.isAuthError {
            self.error = copilotError.localizedDescription
            self.needsAuth = true
        } catch {
            self.error = error.localizedDescription
            self.needsAuth = false
        }
    }

    // MARK: - Private

    private func readToken() throws -> String {
        let path = NSString("~/.config/github-copilot/apps.json").expandingTildeInPath

        guard FileManager.default.fileExists(atPath: path) else {
            throw CopilotError.tokenFileMissing
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let apps = try JSONDecoder().decode([String: CopilotApp].self, from: data)
        guard let firstApp = apps.values.first else {
            throw CopilotError.noToken
        }
        return firstApp.oauthToken
    }

    private func fetchUsage(token: String) async throws -> CopilotUserResponse {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            throw CopilotError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotError.apiError
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw CopilotError.authenticationFailed
        }

        guard httpResponse.statusCode == 200 else {
            throw CopilotError.apiError
        }

        return try JSONDecoder().decode(CopilotUserResponse.self, from: data)
    }
}

enum CopilotError: LocalizedError {
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

extension CopilotService {
    static let previewLowUsage = CopilotService(usage: .lowUsage)
    static let previewMediumUsage = CopilotService(usage: .mediumUsage)
    static let previewHighUsage = CopilotService(usage: .highUsage)
    static let previewAtLimit = CopilotService(usage: .atLimit)
    static let previewOverLimit = CopilotService(usage: .overLimit)
    static let previewSlightlyOver = CopilotService(usage: .slightlyOver)
    static let previewLoading = CopilotService(usage: nil, isLoading: true)
    static let previewError = CopilotService(
        usage: nil,
        error: "No Copilot OAuth token found in ~/.config/github-copilot/apps.json"
    )
    static let previewNeedsAuth = CopilotService(
        usage: nil,
        error: "GitHub Copilot token file not found. Sign in to create it.",
        needsAuth: true
    )
}
