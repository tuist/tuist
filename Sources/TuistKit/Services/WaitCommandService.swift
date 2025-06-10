import Command
import FileSystem
import Foundation
import Noora
import Path
import TuistSupport

struct WaitCommandService {
    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning

    init(
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    func run() async throws {
        guard try await fileSystem.exists(Environment.current.stateDirectory.appending(component: "tuist.pid")) else {
            Noora.current.success("There is not Tuist background process to wait for.")
            return
        }

        try await Noora.current.progressStep(
            message: "Waiting for the Tuist background process to finish...",
            successMessage: "The Tuist background process has finished.",
            errorMessage: nil,
            showSpinner: true
        ) { _ in
            try await waitForProcess()
        }
    }

    private func waitForProcess() async throws {
        try await withTimeout(
            .seconds(10),
            onTimeout: {
                throw WaitCommandError.timeoutReached
            }
        ) {
            while true {
                let isRunning = try await isProcessRunning()

                if !isRunning {
                    return
                }

                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }

    private func isProcessRunning() async throws -> Bool {
        do {
            _ = try await commandRunner.run(
                arguments: [
                    "/usr/bin/pgrep",
                    "-F",
                    Environment.current.stateDirectory.appending(component: "tuist.pid").pathString,
                ]
            ).awaitCompletion()
            // pgrep found the process and it's still running.
            return true
        } catch let error as CommandError {
            switch error {
            case let .terminated(code, stderr: _):
                // When the `pgrep` command terminates with the exit code 1, it signals the process was not found, which we
                // consider a valid response when the process is not running.
                // In all other cases, we re-throw the error.
                guard code == 1 else {
                    throw error
                }
                return false
            default:
                throw error
            }
        }
    }
}

enum WaitCommandError: LocalizedError {
    case timeoutReached

    var type: ErrorType {
        switch self {
        case .timeoutReached:
            return .abort
        }
    }

    var errorDescription: String? {
        switch self {
        case .timeoutReached:
            return "Timeout of 10 seconds reached while waiting for a Tuist background process to finish."
        }
    }
}
