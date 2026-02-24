import Foundation

// MARK: - Device Flow Response Models

struct DeviceCodeResponse: Decodable {
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

struct AccessTokenResponse: Decodable {
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

enum AuthPhase: Equatable {
    case idle
    case awaitingUser(code: String, verificationURL: String)
    case success
    case error(String)
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
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

// MARK: - Service

@Observable
final class GitHubAuthService {
    private(set) var phase: AuthPhase = .idle
    private(set) var isPolling = false

    private var pollingTask: Task<Void, Never>?
    private static let clientID = "Iv1.b507a08c87ecfe98"

    /// Starts the GitHub Device Flow: requests a device code, then polls for the token.
    func startAuthentication() {
        cancel()
        phase = .idle

        pollingTask = Task {
            do {
                let deviceCode = try await requestDeviceCode()

                if Task.isCancelled { return }

                phase = .awaitingUser(
                    code: deviceCode.userCode,
                    verificationURL: deviceCode.verificationUri
                )

                let token = try await pollForToken(
                    deviceCode: deviceCode.deviceCode,
                    interval: deviceCode.interval,
                    expiresIn: deviceCode.expiresIn
                )

                if Task.isCancelled { return }

                try saveToken(token)
                phase = .success
            } catch is CancellationError {
                // Cancelled — no action needed
            } catch let error as AuthError {
                phase = .error(error.localizedDescription)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    /// Cancels any in-progress authentication.
    func cancel() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    /// Resets state back to idle.
    func reset() {
        cancel()
        phase = .idle
    }

    // MARK: - Private

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "client_id": Self.clientID,
            "scope": "copilot"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.deviceCodeRequestFailed
        }

        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    private func pollForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> String {
        isPolling = true
        defer { isPolling = false }

        var currentInterval = interval
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(currentInterval))
            try Task.checkCancellation()

            let tokenResponse = try await requestAccessToken(deviceCode: deviceCode)

            if let token = tokenResponse.accessToken {
                return token
            }

            switch tokenResponse.error {
            case "authorization_pending":
                continue
            case "slow_down":
                currentInterval += 5
            case "expired_token":
                throw AuthError.expired
            case "access_denied":
                throw AuthError.accessDenied
            default:
                continue
            }
        }

        throw AuthError.expired
    }

    private func requestAccessToken(deviceCode: String) async throws -> AccessTokenResponse {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "client_id": Self.clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.deviceCodeRequestFailed
        }

        return try JSONDecoder().decode(AccessTokenResponse.self, from: data)
    }

    private func saveToken(_ token: String) throws {
        let configDir = NSString("~/.config/github-copilot").expandingTildeInPath
        let filePath = (configDir as NSString).appendingPathComponent("apps.json")

        // Create directory if needed
        try FileManager.default.createDirectory(
            atPath: configDir,
            withIntermediateDirectories: true
        )

        let content: [String: [String: String]] = [
            "github.com": ["oauth_token": token]
        ]
        let data = try JSONSerialization.data(
            withJSONObject: content,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: filePath))
    }
}
