import Darwin
import Foundation

@main
struct ProcessHostProbe {
    static func main() async throws {
        if CommandLine.arguments[1] == "child" {
            var mask = sigset_t()
            guard pthread_sigmask(SIG_SETMASK, nil, &mask) == 0 else { exit(1) }
            print("\(sigismember(&mask, SIGTERM)) \(sigismember(&mask, SIGCHLD))")
            return
        }

        var action = sigaction()
        action.__sigaction_u.__sa_handler = CommandLine.arguments[1] == "ignored" ? SIG_IGN : SIG_DFL
        guard sigaction(SIGCHLD, &action, nil) == 0 else { exit(1) }

        try await Task.detached {
            let output = try await executeXCResultTool([CommandLine.arguments[0], "child"])
            guard output.succeeded, output.standardOutput == "0 0\n" else {
                fatalError("Child inherited blocked signals: \(output.standardOutput)")
            }
        }.value
    }
}
