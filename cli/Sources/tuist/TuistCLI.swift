import Dispatch
import Foundation
import Path

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@main
@_documentation(visibility: private)
private enum TuistCLI {
    private static var signalSource: DispatchSourceSignal?

    static func main() async throws {
        let commandTask = Task {
            try await initDependencies { sessionPaths in
                try await TuistCommand.main(
                    logFilePath: sessionPaths.logFilePath,
                    sessionDirectory: sessionPaths.sessionDirectory,
                    networkFilePath: sessionPaths.networkFilePath
                )
            }
        }

        let signalSources = installSignalHandlers {
            commandTask.cancel()
        }
        defer { uninstallSignalHandlers(signalSources) }

        try await commandTask.value
    }

    private static func installSignalHandlers(
        onSignal: @escaping @Sendable () -> Void
    ) -> (DispatchSourceSignal, DispatchSourceSignal) {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let queue = DispatchQueue(label: "dev.tuist.signals", qos: .userInitiated)
        let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)

        interruptSource.setEventHandler(handler: onSignal)
        terminationSource.setEventHandler(handler: onSignal)
        interruptSource.resume()
        terminationSource.resume()
        signalSource = interruptSource

        return (interruptSource, terminationSource)
    }

    private static func uninstallSignalHandlers(
        _ sources: (DispatchSourceSignal, DispatchSourceSignal)
    ) {
        sources.0.cancel()
        sources.1.cancel()
        signalSource = nil
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)
    }
}
