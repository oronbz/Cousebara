import Foundation
import Testing

@testable import Cousebara

struct ISO8601Tests {
    @Test func parsesFractionalSecondsWithOffset() {
        // Exact shape returned by /api/oauth/usage
        let date = ISO8601.date(from: "2026-06-01T10:00:00.049345+00:00")
        #expect(date != nil)
    }

    @Test func parsesWithoutFractionalSeconds() {
        let date = ISO8601.date(from: "2026-06-04T19:00:01+00:00")
        #expect(date != nil)
    }

    @Test func parsesZuluTime() {
        #expect(ISO8601.date(from: "2026-06-01T10:00:00Z") != nil)
    }

    @Test func nilStringReturnsNil() {
        #expect(ISO8601.date(from: nil) == nil)
    }

    @Test func garbageReturnsNil() {
        #expect(ISO8601.date(from: "not-a-date") == nil)
    }
}

struct UsageWindowTests {
    private let reset = ISO8601.date(from: "2026-06-01T10:00:00Z")!
    private let now = ISO8601.date(from: "2026-06-01T07:30:00Z")!  // 2.5h into a 5h window

    private func window(_ util: Double) -> UsageWindow {
        UsageWindow(utilization: util, resetsAt: reset, length: UsageWindow.sessionLength)
    }

    @Test func levelThresholds() {
        #expect(window(0).level == .normal)
        #expect(window(59).level == .normal)
        #expect(window(60).level == .warning)
        #expect(window(84).level == .warning)
        #expect(window(85).level == .high)
        #expect(window(99).level == .high)
        #expect(window(100).level == .maxed)
        #expect(window(120).level == .maxed)
    }

    @Test func fractions() {
        #expect(abs(window(40).fraction - 0.4) < 1e-9)
        #expect(abs(window(40).remainingFraction - 0.6) < 1e-9)
        #expect(window(150).fraction == 1.0)        // clamped
        #expect(window(40).percentRemaining == 60)
    }

    @Test func isMaxed() {
        #expect(window(99).isMaxed == false)
        #expect(window(100).isMaxed == true)
    }

    @Test func paceReserve_midWindow() {
        // 50% time elapsed (2.5h of 5h), 30% used → +20 reserve, under pace
        let pace = window(30).paceReserve(now: now)
        #expect(pace != nil)
        #expect(abs(pace!.percentTimeElapsed - 50) < 0.5)
        #expect(pace!.isUnderPace == true)
        #expect(abs(pace!.reserve - 20) < 0.5)
    }

    @Test func paceReserve_overPace() {
        let pace = window(80).paceReserve(now: now)  // 50% time, 80% used
        #expect(pace!.isUnderPace == false)
        #expect(pace!.reserve < 0)
        #expect(abs(pace!.reserve - (-30)) < 0.5)
    }

    @Test func paceReserve_nilResetReturnsNil() {
        let w = UsageWindow(utilization: 30, resetsAt: nil, length: UsageWindow.sessionLength)
        #expect(w.paceReserve(now: now) == nil)
    }

    @Test func weeklyLengthIsSevenDays() {
        #expect(UsageWindow.weeklyLength == 7 * 24 * 60 * 60)
        #expect(UsageWindow.sessionLength == 5 * 60 * 60)
    }
}

struct GeneralizedPaceReserveTests {
    @Test func weeklyHalfwayUnderPace() {
        let start = ISO8601.date(from: "2026-06-01T00:00:00Z")!
        let end = start.addingTimeInterval(7 * 24 * 60 * 60)
        let now = start.addingTimeInterval(3.5 * 24 * 60 * 60)  // 50% elapsed
        let pace = PaceReserve.calculate(percentUsed: 20, windowStart: start, windowEnd: end, now: now)
        #expect(pace != nil)
        #expect(abs(pace!.percentTimeElapsed - 50) < 0.5)
        #expect(pace!.reserve > 0)
    }

    @Test func zeroLengthReturnsNil() {
        let d = ISO8601.date(from: "2026-06-01T00:00:00Z")!
        #expect(PaceReserve.calculate(percentUsed: 10, windowStart: d, windowEnd: d, now: d) == nil)
    }

    @Test func clampsBeforeAndAfter() {
        let start = ISO8601.date(from: "2026-06-01T00:00:00Z")!
        let end = start.addingTimeInterval(3600)
        let before = PaceReserve.calculate(percentUsed: 0, windowStart: start, windowEnd: end, now: start.addingTimeInterval(-100))
        let after = PaceReserve.calculate(percentUsed: 0, windowStart: start, windowEnd: end, now: end.addingTimeInterval(100))
        #expect(before!.percentTimeElapsed == 0)
        #expect(after!.percentTimeElapsed == 100)
    }
}

struct ClaudeUsageDecodingTests {
    // Captured verbatim from the 2026-06-01 smoke test.
    let json = """
    {"five_hour":{"utilization":7.0,"resets_at":"2026-06-01T10:00:00.049345+00:00"},
     "seven_day":{"utilization":4.0,"resets_at":"2026-06-04T19:00:01.049367+00:00"},
     "seven_day_opus":null,
     "seven_day_sonnet":{"utilization":0.0,"resets_at":null}}
    """.data(using: .utf8)!

    @Test func decodesAndMapsToUsage() throws {
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: json)
        let usage = ClaudeUsage(response: response)
        #expect(usage.session.utilization == 7.0)
        #expect(usage.session.resetsAt != nil)
        #expect(usage.session.length == UsageWindow.sessionLength)
        #expect(usage.weekly.utilization == 4.0)
        #expect(usage.weekly.resetsAt != nil)
        #expect(usage.weekly.length == UsageWindow.weeklyLength)
    }

    @Test func missingWindowsDefaultToZero() throws {
        let usage = ClaudeUsage(response: try JSONDecoder().decode(
            ClaudeUsageResponse.self, from: "{}".data(using: .utf8)!))
        #expect(usage.session.utilization == 0)
        #expect(usage.session.resetsAt == nil)
        #expect(usage.weekly.utilization == 0)
    }
}

struct ClaudeProfileDecodingTests {
    let json = """
    {"account":{"display_name":"Oron","email":"oronb@gett.com"},
     "organization":{"name":"Gett","rate_limit_tier":"default_claude_max_5x"}}
    """.data(using: .utf8)!

    @Test func decodesAndDerivesPlanLabel() throws {
        let response = try JSONDecoder().decode(ClaudeProfileResponse.self, from: json)
        let profile = ClaudeProfile(response: response)
        #expect(profile.displayName == "Oron")
        #expect(profile.email == "oronb@gett.com")
        #expect(profile.orgName == "Gett")
        #expect(profile.planLabel == "Max 5x")
    }

    @Test func humanizeTierHandlesNil() {
        #expect(ClaudeProfile.humanizeTier(nil) == nil)
    }

    @Test func humanizeTierHandlesEmpty() {
        #expect(ClaudeProfile.humanizeTier("") == nil)
    }
}

struct ClaudeErrorTests {
    @Test func authErrorsClassified() {
        #expect(ClaudeError.noToken.isAuthError == true)
        #expect(ClaudeError.keychainDenied.isAuthError == true)
        #expect(ClaudeError.tokenExpired.isAuthError == true)
        #expect(ClaudeError.authenticationFailed.isAuthError == true)
        #expect(ClaudeError.apiError.isAuthError == false)
        #expect(ClaudeError.invalidURL.isAuthError == false)
    }
}
