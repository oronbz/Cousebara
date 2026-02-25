import AppKit
import Dependencies
import DependenciesMacros

@DependencyClient
struct AppTerminator: Sendable {
    var terminate: @Sendable () -> Void
    var relaunch: @Sendable () -> Void
}

extension AppTerminator: TestDependencyKey {
    static var testValue: AppTerminator {
        AppTerminator()
    }

    static var previewValue: AppTerminator {
        AppTerminator(terminate: {}, relaunch: {})
    }
}

extension AppTerminator: DependencyKey {
    static var liveValue: AppTerminator {
        AppTerminator(
            terminate: {
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            },
            relaunch: {
                let appPath = Bundle.main.bundleURL.path
                let pid = ProcessInfo.processInfo.processIdentifier
                let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"\(appPath)\""
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", script]
                try? process.run()
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        )
    }
}
