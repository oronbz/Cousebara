import ComposableArchitecture
import Foundation
import Testing

@testable import Cousebara

@MainActor
struct AuthFeatureTests {
    @Test func signInButtonTapped_requestsDeviceCode() async {
        let clock = TestClock()
        let deviceCodeResponse = DeviceCodeResponse(
            deviceCode: "dc_123",
            userCode: "ABCD-1234",
            verificationUri: "https://github.com/login/device",
            expiresIn: 900,
            interval: 5
        )

        let store = TestStore(initialState: AuthFeature.State()) {
            AuthFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[GitHubAuthClient.self].requestDeviceCode = { deviceCodeResponse }
            $0[GitHubAuthClient.self].requestAccessToken = { _ in
                AccessTokenResponse(
                    accessToken: "gho_test_token",
                    tokenType: "bearer",
                    scope: "copilot",
                    error: nil
                )
            }
            $0[GitHubAuthClient.self].saveToken = { _ in }
        }

        await store.send(.signInButtonTapped)

        await store.receive(\.deviceCodeResponse.success) {
            $0.phase = .awaitingUser(
                code: "ABCD-1234",
                verificationURL: "https://github.com/login/device"
            )
        }

        // Advance clock past the polling interval to unblock pollForToken's sleep
        await clock.advance(by: .seconds(5))

        // Polling returns a token immediately, so we receive tokenPollingResult
        await store.receive(\.tokenPollingResult.success) {
            $0.phase = .success
        }

        // Advance clock past the 1.5s post-success delay
        await clock.advance(by: .seconds(1.5))

        // After success, delegate is sent after the delay
        await store.receive(\.delegate.authenticated)
    }

    @Test func signInButtonTapped_deviceCodeRequestFails() async {
        let store = TestStore(initialState: AuthFeature.State()) {
            AuthFeature()
        } withDependencies: {
            $0[GitHubAuthClient.self].requestDeviceCode = {
                throw AuthError.deviceCodeRequestFailed
            }
        }

        await store.send(.signInButtonTapped)

        await store.receive(\.deviceCodeResponse.failure) {
            $0.phase = .error(AuthError.deviceCodeRequestFailed.localizedDescription)
        }
    }

    @Test func cancelButtonTapped_resetsToIdle() async {
        let store = TestStore(
            initialState: AuthFeature.State(
                phase: .awaitingUser(
                    code: "ABCD-1234",
                    verificationURL: "https://github.com/login/device"
                )
            )
        ) {
            AuthFeature()
        }

        await store.send(.cancelButtonTapped) {
            $0.phase = .idle
        }
    }

    @Test func tryAgainButtonTapped_restartsDeviceCodeRequest() async {
        let clock = TestClock()
        let deviceCodeResponse = DeviceCodeResponse(
            deviceCode: "dc_456",
            userCode: "EFGH-5678",
            verificationUri: "https://github.com/login/device",
            expiresIn: 900,
            interval: 5
        )

        let store = TestStore(
            initialState: AuthFeature.State(
                phase: .error("Previous error")
            )
        ) {
            AuthFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[GitHubAuthClient.self].requestDeviceCode = { deviceCodeResponse }
            $0[GitHubAuthClient.self].requestAccessToken = { _ in
                AccessTokenResponse(
                    accessToken: "gho_new_token",
                    tokenType: "bearer",
                    scope: "copilot",
                    error: nil
                )
            }
            $0[GitHubAuthClient.self].saveToken = { _ in }
        }

        await store.send(.tryAgainButtonTapped) {
            $0.phase = .idle
        }

        await store.receive(\.deviceCodeResponse.success) {
            $0.phase = .awaitingUser(
                code: "EFGH-5678",
                verificationURL: "https://github.com/login/device"
            )
        }

        // Advance past polling interval
        await clock.advance(by: .seconds(5))

        await store.receive(\.tokenPollingResult.success) {
            $0.phase = .success
        }

        // Advance past post-success delay
        await clock.advance(by: .seconds(1.5))

        await store.receive(\.delegate.authenticated)
    }

    @Test func tokenPollingResult_saveTokenFails_showsError() async {
        let clock = TestClock()
        let deviceCodeResponse = DeviceCodeResponse(
            deviceCode: "dc_789",
            userCode: "IJKL-9012",
            verificationUri: "https://github.com/login/device",
            expiresIn: 900,
            interval: 5
        )

        struct SaveError: LocalizedError, Equatable {
            var errorDescription: String? { "Failed to write token file" }
        }

        let store = TestStore(initialState: AuthFeature.State()) {
            AuthFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[GitHubAuthClient.self].requestDeviceCode = { deviceCodeResponse }
            $0[GitHubAuthClient.self].requestAccessToken = { _ in
                AccessTokenResponse(
                    accessToken: "gho_token",
                    tokenType: "bearer",
                    scope: "copilot",
                    error: nil
                )
            }
            $0[GitHubAuthClient.self].saveToken = { _ in throw SaveError() }
        }

        await store.send(.signInButtonTapped)

        await store.receive(\.deviceCodeResponse.success) {
            $0.phase = .awaitingUser(
                code: "IJKL-9012",
                verificationURL: "https://github.com/login/device"
            )
        }

        // Advance past polling interval
        await clock.advance(by: .seconds(5))

        // saveToken fails, so phase goes to error (not success)
        await store.receive(\.tokenPollingResult.success) {
            $0.phase = .error("Failed to write token file")
        }
    }

    @Test func tokenPollingResult_failure_showsError() async {
        let clock = TestClock()

        let store = TestStore(initialState: AuthFeature.State()) {
            AuthFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[GitHubAuthClient.self].requestDeviceCode = {
                DeviceCodeResponse(
                    deviceCode: "dc_expired",
                    userCode: "MNOP-3456",
                    verificationUri: "https://github.com/login/device",
                    expiresIn: 900,
                    interval: 5
                )
            }
            $0[GitHubAuthClient.self].requestAccessToken = { _ in
                throw AuthError.accessDenied
            }
        }

        await store.send(.signInButtonTapped)

        await store.receive(\.deviceCodeResponse.success) {
            $0.phase = .awaitingUser(
                code: "MNOP-3456",
                verificationURL: "https://github.com/login/device"
            )
        }

        // Advance past polling interval so pollForToken's sleep unblocks
        await clock.advance(by: .seconds(5))

        await store.receive(\.tokenPollingResult.failure) {
            $0.phase = .error(AuthError.accessDenied.localizedDescription)
        }
    }
}
