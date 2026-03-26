import Dependencies
import DependenciesMacros
import ServiceManagement

@DependencyClient
struct LaunchAtLoginClient: Sendable {
    var isEnabled: @Sendable () -> Bool = { false }
    var setEnabled: @Sendable (_ enabled: Bool) throws -> Void
}

extension LaunchAtLoginClient: TestDependencyKey {
    static var testValue: LaunchAtLoginClient {
        LaunchAtLoginClient()
    }

    static var previewValue: LaunchAtLoginClient {
        LaunchAtLoginClient(isEnabled: { true }, setEnabled: { _ in })
    }
}

extension LaunchAtLoginClient: DependencyKey {
    static var liveValue: LaunchAtLoginClient {
        LaunchAtLoginClient(
            isEnabled: {
                SMAppService.mainApp.status == .enabled
            },
            setEnabled: { enabled in
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            }
        )
    }
}
