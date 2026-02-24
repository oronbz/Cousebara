import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct PopoverFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var auth: AuthFeature.State?
        var error: String?
        var isLoading = false
        var lastUpdated: Date?
        var login: String?
        var needsAuth = false
        var plan: String?
        var resetDate: String?
        @Shared(.appStorage("showPercentageInMenuBar")) var showPercentage = false
        var usage: QuotaSnapshot?
    }

    enum Action: BindableAction {
        case auth(PresentationAction<AuthFeature.Action>)
        case binding(BindingAction<State>)
        case onAppLaunch
        case quitButtonTapped
        case refreshButtonTapped
        case retryButtonTapped
        case timerTicked
        case usageResponse(Result<CopilotUserResponse, any Error>)
    }

    enum CancelID {
        case timer
    }

    @Dependency(CopilotAPIClient.self) var apiClient
    @Dependency(AppTerminator.self) var appTerminator
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .auth(.presented(.delegate(.authenticated))):
                state.auth = nil
                state.needsAuth = false
                return fetchUsage(state: &state)

            case .auth:
                return .none

            case .binding:
                return .none

            case .onAppLaunch:
                return .merge(
                    fetchUsage(state: &state),
                    .run { send in
                        for await _ in clock.timer(interval: .seconds(15 * 60)) {
                            await send(.timerTicked)
                        }
                    }
                    .cancellable(id: CancelID.timer)
                )

            case .quitButtonTapped:
                return .run { _ in appTerminator.terminate() }

            case .refreshButtonTapped:
                return fetchUsage(state: &state)

            case .retryButtonTapped:
                return fetchUsage(state: &state)

            case .timerTicked:
                return fetchUsage(state: &state)

            case .usageResponse(.success(let response)):
                state.isLoading = false
                state.usage = response.quotaSnapshots?.premiumInteractions
                state.login = response.login
                state.plan = response.copilotPlan
                state.resetDate = response.quotaResetDate
                state.lastUpdated = now
                state.error = nil
                state.needsAuth = false
                return .none

            case .usageResponse(.failure(let error)):
                state.isLoading = false
                if let copilotError = error as? CopilotError, copilotError.isAuthError {
                    state.error = copilotError.localizedDescription
                    state.needsAuth = true
                    state.auth = AuthFeature.State()
                } else {
                    state.error = error.localizedDescription
                    state.needsAuth = false
                }
                return .none
            }
        }
        .ifLet(\.$auth, action: \.auth) {
            AuthFeature()
        }
    }

    // MARK: - Private

    private func fetchUsage(state: inout State) -> Effect<Action> {
        state.isLoading = true
        return .run { send in
            await send(
                .usageResponse(
                    Result {
                        let token = try apiClient.readToken()
                        return try await apiClient.fetchUsage(token)
                    }
                )
            )
        }
    }
}
