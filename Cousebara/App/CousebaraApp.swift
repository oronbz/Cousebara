import ComposableArchitecture
import SwiftUI

@main
struct CousebaraApp: App {
    let store: StoreOf<AppFeature>

    init() {
        let store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.send(.popover(.onAppLaunch))
        self.store = store
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store.scope(state: \.popover, action: \.popover))
        } label: {
            MenuBarLabel(
                session: store.popover.session,
                weekly: store.popover.weekly,
                showPercentage: store.popover.showPercentage,
                showRemaining: store.popover.showRemaining
            )
        }
        .menuBarExtraStyle(.window)
    }
}
