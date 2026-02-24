import ComposableArchitecture

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var popover = PopoverFeature.State()
    }

    enum Action {
        case popover(PopoverFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.popover, action: \.popover) {
            PopoverFeature()
        }
    }
}
