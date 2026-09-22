import ArgumentParser
import Foundation

extension TuistCommand {
    /// When true, the CLI reports its exit code by throwing `EmbeddedExit` instead of
    /// terminating the process, so a host that links Tuist decides when to exit.
    @TaskLocal public static var isEmbedded = false

    /// Ends the run with `code`: exits the process, or throws `EmbeddedExit` when embedded.
    static func terminate(_ code: Int32) throws -> Never {
        if isEmbedded {
            throw EmbeddedExit(code: code)
        }
        _exit(code)
    }

    /// Prints the parser's message for `error` and ends the run with its exit code, the way
    /// `exit(withError:)` does, but without exiting the process when embedded.
    static func terminate(withError error: Error) throws -> Never {
        guard isEmbedded else { exit(withError: error) }
        let code = exitCode(for: error)
        let message = fullMessage(for: error)
        if !message.isEmpty {
            if code == .success {
                print(message)
            } else {
                FileHandle.standardError.write(Data((message + "\n").utf8))
            }
        }
        throw EmbeddedExit(code: code.rawValue)
    }
}
