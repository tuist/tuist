import Foundation
import TuistCLICore

private final class ExitCodeBox: @unchecked Sendable {
    var value: Int32 = 0
}

/// Runs the Tuist CLI in-process with the given argv (argv[0] included) and returns its exit code.
/// Call at most once per process: logging bootstrap and other setup in `initDependencies` are process-wide.
@_cdecl("tuist_run")
public func tuistRun(_ argc: Int32, _ argv: UnsafePointer<UnsafePointer<CChar>?>?) -> Int32 {
    var arguments: [String] = []
    if let argv {
        for index in 0 ..< Int(argc) {
            if let argument = argv[index] {
                arguments.append(String(cString: argument))
            }
        }
    }

    let exitCode = ExitCodeBox()
    let finished = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            try await initDependencies { sessionPaths in
                try await TuistCommand.main(
                    logFilePath: sessionPaths.logFilePath,
                    sessionDirectory: sessionPaths.sessionDirectory,
                    networkFilePath: sessionPaths.networkFilePath,
                    arguments
                )
            }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exitCode.value = 1
        }
        finished.signal()
    }
    finished.wait()
    return exitCode.value
}
