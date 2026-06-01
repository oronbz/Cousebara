import ComposableArchitecture
import Foundation
import Testing

@testable import Cousebara

@MainActor
struct PopoverFeatureTests {
    let fixedDate = ISO8601.date(from: "2026-06-01T07:30:00Z")!

    func makeUsage(session: Double = 35, weekly: Double = 20) -> ClaudeUsage {
        ClaudeUsage(
            session: UsageWindow(
                utilization: session,
                resetsAt: ISO8601.date(from: "2026-06-01T10:00:00Z"),
                length: UsageWindow.sessionLength
            ),
            weekly: UsageWindow(
                utilization: weekly,
                resetsAt: ISO8601.date(from: "2026-06-07T00:00:00Z"),
                length: UsageWindow.weeklyLength
            )
        )
    }

    let profile = ClaudeProfile(
        displayName: "testuser",
        email: "test@example.com",
        orgName: "Gett",
        planLabel: "Max 5X"
    )

    let currentRelease = GitHubRelease(
        tagName: "v1.4.0",
        htmlUrl: "https://github.com/oronbz/cousebara/releases/tag/v1.4.0"
    )

    @Test func refreshButtonTapped_setsSessionWeeklyAndProfile() async {
        let usage = makeUsage()
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "mock-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in usage }
            $0[ClaudeAPIClient.self].fetchProfile = { _ in profile }
            $0.date = .constant(fixedDate)
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.session = usage.session
            $0.weekly = usage.weekly
            $0.weeklyPace = usage.weekly.paceReserve(now: fixedDate)
            $0.lastUpdated = fixedDate
            $0.error = nil
            $0.needsLogin = false
        }

        await store.receive(\.profileResponse.success) {
            $0.profile = profile
        }
    }

    @Test func retryButtonTapped_clearsErrorAndFetches() async {
        let usage = makeUsage()
        let store = TestStore(
            initialState: PopoverFeature.State(error: "Previous error")
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "mock-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in usage }
            $0[ClaudeAPIClient.self].fetchProfile = { _ in profile }
            $0.date = .constant(fixedDate)
        }

        await store.send(.retryButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.error = nil
            $0.session = usage.session
            $0.weekly = usage.weekly
            $0.weeklyPace = usage.weekly.paceReserve(now: fixedDate)
            $0.lastUpdated = fixedDate
        }

        await store.receive(\.profileResponse.success) {
            $0.profile = profile
        }
    }

    @Test func fetchUsage_noToken_setsNeedsLogin() async {
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { throw ClaudeError.noToken }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.failure) {
            $0.isLoading = false
            $0.error = ClaudeError.noToken.localizedDescription
            $0.needsLogin = true
        }
    }

    @Test func fetchUsage_authenticationFailed_setsNeedsLogin() async {
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "mock-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in throw ClaudeError.authenticationFailed }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.failure) {
            $0.isLoading = false
            $0.error = ClaudeError.authenticationFailed.localizedDescription
            $0.needsLogin = true
        }
    }

    @Test func fetchUsage_apiError_setsErrorNotNeedsLogin() async {
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "mock-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in throw ClaudeError.apiError }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.failure) {
            $0.isLoading = false
            $0.error = ClaudeError.apiError.localizedDescription
            $0.needsLogin = false
        }
    }

    @Test func profileFailure_isNonFatal() async {
        let usage = makeUsage()
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "mock-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in usage }
            $0[ClaudeAPIClient.self].fetchProfile = { _ in throw ClaudeError.apiError }
            $0.date = .constant(fixedDate)
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.session = usage.session
            $0.weekly = usage.weekly
            $0.weeklyPace = usage.weekly.paceReserve(now: fixedDate)
            $0.lastUpdated = fixedDate
        }

        await store.receive(\.profileResponse.failure)
        #expect(store.state.profile == nil)
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

    @Test func onAppLaunch_fetchesUsageProfileAndStartsTimer() async {
        let clock = TestClock()
        let usage = makeUsage()
        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "mock-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in usage }
            $0[ClaudeAPIClient.self].fetchProfile = { _ in profile }
            $0[VersionClient.self].currentVersion = { "1.4.0" }
            $0[VersionClient.self].fetchLatestRelease = { currentRelease }
            $0[VersionClient.self].onDiskVersion = { "1.4.0" }
            $0[LaunchAtLoginClient.self].isEnabled = { true }
            $0[LaunchAtLoginClient.self].setEnabled = { _ in }
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
            $0.session = usage.session
            $0.weekly = usage.weekly
            $0.weeklyPace = usage.weekly.paceReserve(now: fixedDate)
            $0.lastUpdated = fixedDate
        }

        await store.receive(\.profileResponse.success) {
            $0.profile = profile
        }

        await clock.advance(by: .seconds(15 * 60))

        await store.receive(\.timerTicked) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
        }

        await store.skipInFlightEffects()
    }

    @Test func onAppear_fetchesUsageAndRestartsTimer() async {
        let clock = TestClock()
        let usage = makeUsage()
        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "mock-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in usage }
            $0[ClaudeAPIClient.self].fetchProfile = { _ in profile }
            $0[VersionClient.self].fetchLatestRelease = { currentRelease }
            $0.continuousClock = clock
            $0.date = .constant(fixedDate)
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.session = usage.session
            $0.weekly = usage.weekly
        }

        await store.receive(\.profileResponse.success) {
            $0.profile = profile
        }

        await clock.advance(by: .seconds(15 * 60))

        await store.receive(\.timerTicked) {
            $0.isLoading = true
        }

        await store.skipInFlightEffects()
    }

    @Test func onAppear_withinCacheWindow_skipsFetch() async {
        // Last refresh was 30s ago (< 60s cache window) → opening the popover must NOT refetch.
        let store = TestStore(
            initialState: PopoverFeature.State(lastUpdated: fixedDate)
        ) {
            PopoverFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate.addingTimeInterval(30))
        }

        // onAppear returns no effect → no usageResponse/profileResponse received.
        await store.send(.onAppear)
    }

    @Test func onAppear_afterCacheWindow_refetches() async {
        // Last refresh was 120s ago (> 60s) → opening the popover refetches.
        let clock = TestClock()
        let usage = makeUsage()
        let store = TestStore(
            initialState: PopoverFeature.State(lastUpdated: fixedDate)
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "mock-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in usage }
            $0[ClaudeAPIClient.self].fetchProfile = { _ in profile }
            $0[VersionClient.self].fetchLatestRelease = { currentRelease }
            $0.continuousClock = clock
            $0.date = .constant(fixedDate.addingTimeInterval(120))
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
            $0.lastUpdated = fixedDate.addingTimeInterval(120)
        }

        await store.receive(\.profileResponse.success) {
            $0.profile = profile
        }

        await store.skipInFlightEffects()
    }

    // MARK: - Version Check

    @Test func versionCheck_newerAvailable_showsBanner() async {
        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        }

        await store.send(.versionCheckResponse(.success(GitHubRelease(
            tagName: "v1.5.0", htmlUrl: "")))) {
            $0.availableUpdate = "1.5.0"
        }
    }

    @Test func versionCheck_upToDate_noBanner() async {
        let store = TestStore(
            initialState: PopoverFeature.State(currentVersion: "1.4.0")
        ) {
            PopoverFeature()
        }

        await store.send(.versionCheckResponse(.success(currentRelease)))
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
            initialState: PopoverFeature.State(availableUpdate: "1.5.0", currentVersion: "1.4.0")
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

    // MARK: - Auto-Relaunch

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

    // MARK: - Launch at Login

    @Test func launchAtLoginToggled_enablesSuccessfully() async {
        let store = TestStore(
            initialState: PopoverFeature.State(launchAtLogin: false)
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[LaunchAtLoginClient.self].setEnabled = { _ in }
            $0[LaunchAtLoginClient.self].isEnabled = { true }
        }

        await store.send(.launchAtLoginToggled(true)) {
            $0.launchAtLogin = true
        }
        await store.receive(\.launchAtLoginLoaded)
    }

    @Test func launchAtLoginToggled_failureRevertsState() async {
        struct RegistrationError: Error {}
        let store = TestStore(
            initialState: PopoverFeature.State(launchAtLogin: false)
        ) {
            PopoverFeature()
        } withDependencies: {
            $0[LaunchAtLoginClient.self].setEnabled = { _ in throw RegistrationError() }
            $0[LaunchAtLoginClient.self].isEnabled = { false }
        }

        await store.send(.launchAtLoginToggled(true)) {
            $0.launchAtLogin = true
        }
        await store.receive(\.launchAtLoginLoaded) {
            $0.launchAtLogin = false
        }
    }
}
