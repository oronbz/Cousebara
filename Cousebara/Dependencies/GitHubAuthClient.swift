import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct GitHubAuthClient: Sendable {
    var requestDeviceCode: @Sendable () async throws -> DeviceCodeResponse
    var requestAccessToken: @Sendable (_ deviceCode: String) async throws -> AccessTokenResponse
    var saveToken: @Sendable (_ token: String) throws -> Void
}

extension GitHubAuthClient: TestDependencyKey {
    static var previewValue: GitHubAuthClient {
        GitHubAuthClient(
            requestDeviceCode: {
                DeviceCodeResponse(
                    deviceCode: "preview-device-code",
                    userCode: "ABCD-1234",
                    verificationUri: "https://github.com/login/device",
                    expiresIn: 900,
                    interval: 5
                )
            },
            requestAccessToken: { _ in
                AccessTokenResponse(
                    accessToken: "gho_preview_token_1234567890",
                    tokenType: "bearer",
                    scope: "copilot",
                    error: nil
                )
            },
            saveToken: { _ in }
        )
    }
}

extension GitHubAuthClient: DependencyKey {
    private static let clientID = "Iv1.b507a08c87ecfe98"

    static var liveValue: GitHubAuthClient {
        GitHubAuthClient(
            requestDeviceCode: {
                let url = URL(string: "https://github.com/login/device/code")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let body: [String: String] = [
                    "client_id": clientID,
                    "scope": "copilot",
                ]
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw AuthError.deviceCodeRequestFailed
                }

                return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
            },
            requestAccessToken: { deviceCode in
                let url = URL(string: "https://github.com/login/oauth/access_token")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let body: [String: String] = [
                    "client_id": clientID,
                    "device_code": deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ]
                request.httpBody = try JSONEncoder().encode(body)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw AuthError.deviceCodeRequestFailed
                }

                return try JSONDecoder().decode(AccessTokenResponse.self, from: data)
            },
            saveToken: { token in
                let configDir = NSString("~/.config/github-copilot").expandingTildeInPath
                let filePath = (configDir as NSString).appendingPathComponent("apps.json")

                try FileManager.default.createDirectory(
                    atPath: configDir,
                    withIntermediateDirectories: true
                )

                let content: [String: [String: String]] = [
                    "github.com": ["oauth_token": token],
                ]
                let data = try JSONSerialization.data(
                    withJSONObject: content,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try data.write(to: URL(fileURLWithPath: filePath))
            }
        )
    }
}
