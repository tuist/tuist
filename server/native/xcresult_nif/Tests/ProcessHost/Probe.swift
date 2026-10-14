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
        action.__sigaction_u.__sa_handler = CommandLine.arguments[1] == "default" ? SIG_DFL : SIG_IGN
        guard sigaction(SIGCHLD, &action, nil) == 0 else { exit(1) }

        if CommandLine.arguments[1] == "beam" {
            try await runLikeTheBEAM()
            return
        }

        for command in ["exit 0", "printf failure >&2; exit 3", "kill -9 $$"] {
            let output = try await executeXCResultTool(["/bin/sh", "-c", "printf '%s' $$; " + command])
            guard output.succeeded == (command == "exit 0"),
                  output.standardError == (command.contains("failure") ? "failure" : ""),
                  let child = pid_t(output.standardOutput)
            else {
                fatalError("Incorrect child output or exit status for: \(command)")
            }
            var status: Int32 = 0
            let result = waitpid(child, &status, WNOHANG)
            guard result == -1, errno == ECHILD else {
                fatalError("Child was not reaped: waitpid returned \(result)")
            }
        }

        try await Task.detached {
            let output = try await executeXCResultTool([CommandLine.arguments[0], "child"])
            guard output.succeeded, output.standardOutput == "0 0\n" else {
                fatalError("Child inherited blocked signals: \(output.standardOutput)")
            }
        }.value
    }

    /// The BEAM ignores SIGCHLD and keeps `erl_child_setup` alive for its whole life. The kernel
    /// posts `NOTE_EXIT` before it reaps a child of such a parent, so reaping can reach a child
    /// that has not finished exiting, which this reproduces deterministically with one that has
    /// not exited at all.
    static func runLikeTheBEAM() async throws {
        let sibling = try spawn("/bin/sleep", "600")
        defer { kill(sibling, SIGKILL) }

        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            fputs("Reaping a child blocked on a long-lived sibling\n", stderr)
            kill(sibling, SIGKILL)
            exit(2)
        }

        try reapExitedChild(try spawn("/bin/sleep", "1"))

        let output = try await executeXCResultTool(["/usr/bin/true"])
        guard output.succeeded else { fatalError("/usr/bin/true failed next to a long-lived sibling") }
    }

    static func spawn(_ arguments: String...) throws -> pid_t {
        var processIdentifier: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let result = posix_spawn(&processIdentifier, arguments[0], nil, nil, &argv, environ)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return processIdentifier
    }
}
