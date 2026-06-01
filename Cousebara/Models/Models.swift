import Foundation

// MARK: - GitHub Release (app self-update — unrelated to Copilot)

struct GitHubRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }

    /// The version string with the "v" prefix stripped (e.g. "1.5.0")
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// Returns `true` when `self` represents a newer version than `currentVersion`.
    func isNewer(than currentVersion: String) -> Bool {
        let latest = version.split(separator: ".").compactMap { Int($0) }
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(latest.count, current.count) {
            let l = i < latest.count ? latest[i] : 0
            let c = i < current.count ? current[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}

// MARK: - Version Errors

enum VersionError: LocalizedError, Equatable {
    case invalidURL
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid version check URL"
        case .fetchFailed: "Failed to check for updates"
        }
    }
}

// MARK: - Pace Reserve

struct PaceReserve: Equatable, Sendable {
    let percentTimeElapsed: Double
    let reserve: Double

    var isUnderPace: Bool { reserve >= 0 }
    var absoluteReserve: Double { abs(reserve) }
}

extension PaceReserve {
    static let underPace = PaceReserve(percentTimeElapsed: 50, reserve: 20)
    static let onPace = PaceReserve(percentTimeElapsed: 50, reserve: 0)
    static let overPace = PaceReserve(percentTimeElapsed: 50, reserve: -15)
}
