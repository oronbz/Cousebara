import AppKit
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct VersionClient: Sendable {
    var currentVersion: @Sendable () -> String = { "0.0.0" }
    var fetchLatestRelease: @Sendable () async throws -> GitHubRelease
    var copyUpdateCommand: @Sendable () -> Void
}

extension VersionClient: TestDependencyKey {
    static var previewValue: VersionClient {
        VersionClient(
            currentVersion: { "1.4.0" },
            fetchLatestRelease: {
                GitHubRelease(tagName: "v1.4.0", htmlUrl: "https://github.com/oronbz/cousebara/releases/tag/v1.4.0")
            },
            copyUpdateCommand: {}
        )
    }
}

extension VersionClient: DependencyKey {
    static var liveValue: VersionClient {
        VersionClient(
            currentVersion: {
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            },
            fetchLatestRelease: {
                guard let url = URL(string: "https://api.github.com/repos/oronbz/cousebara/releases/latest") else {
                    throw VersionError.invalidURL
                }

                var request = URLRequest(url: url)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200
                else {
                    throw VersionError.fetchFailed
                }

                return try JSONDecoder().decode(GitHubRelease.self, from: data)
            },
            copyUpdateCommand: {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("brew update && brew upgrade --cask cousebara", forType: .string)
            }
        )
    }
}
