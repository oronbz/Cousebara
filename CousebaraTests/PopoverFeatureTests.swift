import ComposableArchitecture
import Foundation
import Testing

@testable import Cousebara

@MainActor
struct PopoverFeatureTests {
    let fixedDate = Date(timeIntervalSince1970: 1_000_000)

    let response = CopilotUserResponse(
        login: "testuser",
        copilotPlan: "enterprise",
        quotaResetDate: "2026-03-01",
        quotaSnapshots: QuotaSnapshots(
            premiumInteractions: .mediumUsage
        )
    )

    let currentRelease = GitHubRelease(
        tagName: "v1.4.0",
        htmlUrl: "https://github.com/oronbz/cousebara/releases/tag/v1.4.0"
    )

    @Test func onAppLaunch_fetchesUsageAndStartsTimer() async {
        let clock = TestClock()

        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
            $0[VersionClient.self].currentVersion = { "1.4.0" }
            $0[VersionClient.self].fetchLatestRelease = { currentRelease }
            $0[VersionClient.self].onDiskVersion = { "1.4.0" }
            $0.continuousClock = clock
            $0.date = .constant(fixedDate)
        }

        // Non-exhaustive because advancing 15 minutes also triggers
        // the 30-second bundle version check timer multiple times
        store.exhaustivity = .off

        await store.send(.onAppLaunch) {
            $0.currentVersion = "1.4.0"
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.login = "testuser"
            $0.plan = "enterprise"
            $0.resetDate = "2026-03-01"
            $0.usage = .mediumUsage
            $0.lastUpdated = fixedDate
        }

        await store.receive(\.versionCheckResponse.success)

        // Advance clock by 15 minutes to trigger timer tick
        await clock.advance(by: .seconds(15 * 60))

        await store.receive(\.timerTicked) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
        }

        await store.receive(\.versionCheckResponse.success)

        // Timers are still running, cancel them
        await store.skipInFlightEffects()
    }

    @Test func popoverAppeared_fetchesUsageAndRestartsTimer() async {
        let clock = TestClock()

        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
            $0[VersionClient.self].fetchLatestRelease = { currentRelease }
            $0.continuousClock = clock
            $0.date = .constant(fixedDate)
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.login = "testuser"
            $0.plan = "enterprise"
            $0.resetDate = "2026-03-01"
            $0.usage = .mediumUsage
            $0.lastUpdated = fixedDate
        }

        await store.receive(\.versionCheckResponse.success)

        // Timer is running — verify it ticks
        await clock.advance(by: .seconds(15 * 60))

        await store.receive(\.timerTicked) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
        }

        await store.receive(\.versionCheckResponse.success)

        await store.skipInFlightEffects()
    }

    @Test func refreshButtonTapped_fetchesUsage() async {
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in
                CopilotUserResponse(
                    login: "testuser",
                    copilotPlan: "business",
                    quotaResetDate: "2026-04-01",
                    quotaSnapshots: QuotaSnapshots(
                        premiumInteractions: .highUsage
                    )
                )
            }
            $0.date = .constant(fixedDate)
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.login = "testuser"
            $0.plan = "business"
            $0.resetDate = "2026-04-01"
            $0.usage = .highUsage
            $0.lastUpdated = fixedDate
        }
    }

    @Test func retryButtonTapped_clearsErrorAndFetchesUsage() async {
        let store = TestStore(
            initialState: PopoverFeature.State(error: "Previous error")
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
            $0.date = .constant(fixedDate)
        }

        await store.send(.retryButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.error = nil
            $0.login = "testuser"
            $0.plan = "enterprise"
            $0.resetDate = "2026-03-01"
            $0.usage = .mediumUsage
            $0.lastUpdated = fixedDate
        }
    }

    @Test func fetchUsage_tokenFileMissing_showsAuthFlow() async {
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { throw CopilotError.tokenFileMissing }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.failure) {
            $0.isLoading = false
            $0.error = CopilotError.tokenFileMissing.localizedDescription
            $0.needsAuth = true
            $0.auth = AuthFeature.State()
        }
    }

    @Test func fetchUsage_authenticationFailed_showsAuthFlow() async {
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in throw CopilotError.authenticationFailed }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.failure) {
            $0.isLoading = false
            $0.error = CopilotError.authenticationFailed.localizedDescription
            $0.needsAuth = true
            $0.auth = AuthFeature.State()
        }
    }

    @Test func fetchUsage_apiError_showsErrorWithoutAuth() async {
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in throw CopilotError.apiError }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.failure) {
            $0.isLoading = false
            $0.error = CopilotError.apiError.localizedDescription
            $0.needsAuth = false
        }
    }

    @Test func authDelegate_authenticated_dismissesAuthAndFetchesUsage() async {
        let store = TestStore(
            initialState: PopoverFeature.State(
                auth: AuthFeature.State(phase: .success),
                error: "GitHub Copilot token file not found. Sign in to create it.",
                needsAuth: true
            )
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
            $0.date = .constant(fixedDate)
        }

        await store.send(.auth(.presented(.delegate(.authenticated)))) {
            $0.auth = nil
            $0.needsAuth = false
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.error = nil
            $0.login = "testuser"
            $0.plan = "enterprise"
            $0.resetDate = "2026-03-01"
            $0.usage = .mediumUsage
            $0.lastUpdated = fixedDate
        }
    }

    @Test func fetchUsage_overLimit_setsCorrectState() async {
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in
                CopilotUserResponse(
                    login: "testuser",
                    copilotPlan: "enterprise",
                    quotaResetDate: "2026-03-01",
                    quotaSnapshots: QuotaSnapshots(
                        premiumInteractions: .overLimit
                    )
                )
            }
            $0.date = .constant(fixedDate)
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.login = "testuser"
            $0.plan = "enterprise"
            $0.resetDate = "2026-03-01"
            $0.usage = .overLimit
            $0.lastUpdated = fixedDate
        }
    }

    @Test func quitButtonTapped_terminatesApp() async {
        var terminateCalled = false

        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[AppTerminator.self].terminate = { terminateCalled = true }
        }

        await store.send(.quitButtonTapped)

        #expect(terminateCalled)
    }

    // MARK: - Version Check Tests

    @Test func versionCheck_newerAvailable_showsBanner() async {
        let newerRelease = GitHubRelease(
            tagName: "v1.5.0",
            htmlUrl: "https://github.com/oronbz/cousebara/releases/tag/v1.5.0"
        )

        let clock = TestClock()

        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
            $0[VersionClient.self].currentVersion = { "1.4.0" }
            $0[VersionClient.self].fetchLatestRelease = { newerRelease }
            $0[VersionClient.self].onDiskVersion = { "1.4.0" }
            $0.continuousClock = clock
            $0.date = .constant(fixedDate)
        }

        store.exhaustivity = .off

        await store.send(.onAppLaunch) {
            $0.currentVersion = "1.4.0"
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.login = "testuser"
            $0.plan = "enterprise"
            $0.resetDate = "2026-03-01"
            $0.usage = .mediumUsage
            $0.lastUpdated = fixedDate
        }

        await store.receive(\.versionCheckResponse.success) {
            $0.availableUpdate = "1.5.0"
        }

        await store.skipInFlightEffects()
    }

    @Test func versionCheck_upToDate_noBanner() async {
        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        }

        await store.send(.versionCheckResponse(.success(currentRelease)))
    }

    @Test func versionCheck_olderRelease_noBanner() async {
        let olderRelease = GitHubRelease(
            tagName: "v1.3.0",
            htmlUrl: "https://github.com/oronbz/cousebara/releases/tag/v1.3.0"
        )

        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        }

        await store.send(.versionCheckResponse(.success(olderRelease)))
    }

    @Test func versionCheck_failure_silentlyIgnored() async {
        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        }

        await store.send(.versionCheckResponse(.failure(VersionError.fetchFailed)))
    }

    @Test func updateBannerTapped_copiesToClipboard() async {
        let clock = TestClock()
        var copyCalled = false

        let store = TestStore(
            initialState: PopoverFeature.State(
                availableUpdate: "1.5.0",
                currentVersion: "1.4.0"
            )
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[VersionClient.self].copyUpdateCommand = { copyCalled = true }
            $0.continuousClock = clock
        }

        await store.send(.updateBannerTapped) {
            $0.showCopiedConfirmation = true
        }

        #expect(copyCalled)

        await clock.advance(by: .seconds(2))

        await store.receive(\.copiedConfirmationDismissed) {
            $0.showCopiedConfirmation = false
        }
    }

    // MARK: - Auto-Relaunch Tests

    @Test func bundleVersionCheck_differentVersion_relaunches() async {
        var relaunchCalled = false

        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[VersionClient.self].onDiskVersion = { "1.5.0" }
            $0[AppTerminator.self].relaunch = { relaunchCalled = true }
        }

        await store.send(.bundleVersionCheckTicked)

        #expect(relaunchCalled)
    }

    @Test func bundleVersionCheck_sameVersion_doesNotRelaunch() async {
        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[VersionClient.self].onDiskVersion = { "1.4.0" }
        }

        await store.send(.bundleVersionCheckTicked)
    }

    @Test func bundleVersionCheck_nilDiskVersion_doesNotRelaunch() async {
        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[VersionClient.self].onDiskVersion = { nil }
        }

        await store.send(.bundleVersionCheckTicked)
    }

    @Test func bundleVersionCheck_nilCurrentVersion_doesNotRelaunch() async {
        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: nil)
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[VersionClient.self].onDiskVersion = { "1.5.0" }
        }

        await store.send(.bundleVersionCheckTicked)
    }

    @Test func versionCheck_newerAvailable_setsAvailableUpdate() async {
        let newerRelease = GitHubRelease(
            tagName: "v2.0.0",
            htmlUrl: "https://github.com/oronbz/cousebara/releases/tag/v2.0.0"
        )

        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        }

        await store.send(.versionCheckResponse(.success(newerRelease))) {
            $0.availableUpdate = "2.0.0"
        }
    }
}
