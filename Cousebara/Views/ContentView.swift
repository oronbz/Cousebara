import ComposableArchitecture
import SwiftUI

struct ContentView: View {
    let store: StoreOf<PopoverFeature>

    var body: some View {
        PopoverView(store: store)
    }
}

#Preview("Normal Usage") {
    ContentView(
        store: Store(initialState: PopoverFeature.State(
            login: "oronbz",
            plan: "enterprise",
            resetDate: "2026-03-01",
            usage: .mediumUsage
        )) {
            PopoverFeature()
        }
    )
}

#Preview("Over Limit") {
    ContentView(
        store: Store(initialState: PopoverFeature.State(
            login: "oronbz",
            plan: "enterprise",
            resetDate: "2026-03-01",
            usage: .overLimit
        )) {
            PopoverFeature()
        }
    )
}
