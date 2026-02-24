import AppKit
import Dependencies
import DependenciesMacros

@DependencyClient
struct AppTerminator: Sendable {
    var terminate: @Sendable () -> Void
}

extension AppTerminator: TestDependencyKey {
    static var testValue: AppTerminator {
        AppTerminator()
    }

    static var previewValue: AppTerminator {
        AppTerminator(terminate: {})
    }
}

extension AppTerminator: DependencyKey {
    static var liveValue: AppTerminator {
        AppTerminator(terminate: {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        })
    }
}
