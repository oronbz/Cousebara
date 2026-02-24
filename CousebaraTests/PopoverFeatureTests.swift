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

    @Test func onAppLaunch_fetchesUsageAndStartsTimer() async {
        let clock = TestClock()

        let store = TestStore(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
            $0.continuousClock = clock
            $0.date = .constant(fixedDate)
        }

        await store.send(.onAppLaunch) {
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

        // Advance clock by 15 minutes to trigger timer tick
        await clock.advance(by: .seconds(15 * 60))

        await store.receive(\.timerTicked) {
            $0.isLoading = true
        }

        await store.receive(\.usageResponse.success) {
            $0.isLoading = false
        }

        // Timer is still running, cancel it
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
}
