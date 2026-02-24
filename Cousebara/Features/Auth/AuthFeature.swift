import ComposableArchitecture
import Foundation

@Reducer
struct AuthFeature {
    @ObservableState
    struct State: Equatable {
        var phase: AuthPhase = .idle
    }

    enum Action {
        case cancelButtonTapped
        case deviceCodeResponse(Result<DeviceCodeResponse, any Error>)
        case signInButtonTapped
        case tokenPollingResult(Result<String, any Error>)
        case tryAgainButtonTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate {
            case authenticated
        }
    }

    enum CancelID {
        case polling
    }

    @Dependency(GitHubAuthClient.self) var authClient
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .cancelButtonTapped:
                state.phase = .idle
                return .cancel(id: CancelID.polling)

            case .deviceCodeResponse(.success(let deviceCode)):
                state.phase = .awaitingUser(
                    code: deviceCode.userCode,
                    verificationURL: deviceCode.verificationUri
                )
                return .run { send in
                    await send(
                        .tokenPollingResult(
                            Result {
                                try await pollForToken(
                                    deviceCode: deviceCode.deviceCode,
                                    interval: deviceCode.interval,
                                    expiresIn: deviceCode.expiresIn
                                )
                            }
                        )
                    )
                }
                .cancellable(id: CancelID.polling)

            case .deviceCodeResponse(.failure(let error)):
                state.phase = .error(error.localizedDescription)
                return .none

            case .signInButtonTapped:
                state.phase = .idle
                return .run { send in
                    await send(
                        .deviceCodeResponse(
                            Result { try await authClient.requestDeviceCode() }
                        )
                    )
                }

            case .tokenPollingResult(.success(let token)):
                do {
                    try authClient.saveToken(token)
                    state.phase = .success
                    return .run { send in
                        try await clock.sleep(for: .seconds(1.5))
                        await send(.delegate(.authenticated))
                    }
                } catch {
                    state.phase = .error(error.localizedDescription)
                    return .none
                }

            case .tokenPollingResult(.failure(let error)):
                state.phase = .error(error.localizedDescription)
                return .none

            case .tryAgainButtonTapped:
                state.phase = .idle
                return .run { send in
                    await send(
                        .deviceCodeResponse(
                            Result { try await authClient.requestDeviceCode() }
                        )
                    )
                }

            case .delegate:
                return .none
            }
        }
    }

    // MARK: - Private

    private func pollForToken(
        deviceCode: String,
        interval: Int,
        expiresIn: Int
    ) async throws -> String {
        var currentInterval = interval
        var elapsed = 0

        while elapsed < expiresIn {
            try Task.checkCancellation()
            try await clock.sleep(for: .seconds(currentInterval))
            elapsed += currentInterval
            try Task.checkCancellation()

            let tokenResponse = try await authClient.requestAccessToken(deviceCode)

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
}
