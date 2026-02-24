import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct CopilotAPIClient: Sendable {
    var readToken: @Sendable () throws -> String
    var fetchUsage: @Sendable (_ token: String) async throws -> CopilotUserResponse
}

extension CopilotAPIClient: TestDependencyKey {
    static var previewValue: CopilotAPIClient {
        CopilotAPIClient(
            readToken: { "preview-token" },
            fetchUsage: { _ in
                CopilotUserResponse(
                    login: "preview-user",
                    copilotPlan: "business",
                    quotaResetDate: "2026-03-01T00:00:00Z",
                    quotaSnapshots: QuotaSnapshots(
                        premiumInteractions: .mediumUsage
                    )
                )
            }
        )
    }
}

extension CopilotAPIClient: DependencyKey {
    static var liveValue: CopilotAPIClient {
        CopilotAPIClient(
            readToken: {
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
            },
            fetchUsage: { token in
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
        )
    }
}
