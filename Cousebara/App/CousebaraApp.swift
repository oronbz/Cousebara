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
                usage: store.popover.usage,
                showPercentage: store.popover.showPercentage
            )
        }
        .menuBarExtraStyle(.window)
    }
}
