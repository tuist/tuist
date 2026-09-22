import Foundation
import Synchronization
import TuistCLICore

private final class ExitCodeBox: @unchecked Sendable {
    var value: Int32 = 0
}

/// Exit code returned when `tuist_run` is called a second time in one process.
private let alreadyRanExitCode: Int32 = 70

private let hasRun = Atomic<Bool>(false)

/// Runs the Tuist CLI in-process with the given argv (argv[0] included) and returns its exit code.
///
/// Call it at most once per process: `initDependencies` bootstraps logging and other
/// process-wide state that cannot be set up twice. A second call prints an error and
/// returns `alreadyRanExitCode` without running anything.
@_cdecl("tuist_run")
public func tuistRun(_ argc: Int32, _ argv: UnsafePointer<UnsafePointer<CChar>?>?) -> Int32 {
    guard !hasRun.exchange(true, ordering: .sequentiallyConsistent) else {
        FileHandle.standardError.write(Data("tuist_run can only be called once per process\n".utf8))
        return alreadyRanExitCode
    }

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
            try await TuistCommand.$isEmbedded.withValue(true) {
                try await initDependencies { sessionPaths in
                    try await TuistCommand.main(
                        logFilePath: sessionPaths.logFilePath,
                        sessionDirectory: sessionPaths.sessionDirectory,
                        networkFilePath: sessionPaths.networkFilePath,
                        arguments
                    )
                }
            }
        } catch let embeddedExit as EmbeddedExit {
            exitCode.value = embeddedExit.code
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exitCode.value = 1
        }
        finished.signal()
    }
    finished.wait()
    return exitCode.value
}
