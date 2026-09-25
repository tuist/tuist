import Darwin
import Foundation
import TuistProcess

@main
struct ProcessSchemeIntegrationProbe {
    static func main() async throws {
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2])
        let mode = CommandLine.arguments[1]
        do {
            if mode == "worker" {
                for _ in 0 ..< 200 where getppid() != 1 {
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard getppid() == 1 else { throw ProbeError.parentDidNotExit }
            }

            var action = sigaction()
            guard sigaction(SIGCHLD, nil, &action) == 0,
                  unsafeBitCast(action.__sigaction_u.__sa_handler, to: UInt.self) != unsafeBitCast(SIG_IGN, to: UInt.self)
            else { throw ProbeError.ignoredChildExitSignal }

            let output = try await CommandRunner().run(arguments: ["/usr/bin/xcrun", "--find", "clang"])
                .concatenatedString(including: [.standardOutput])
            guard FileManager.default.isExecutableFile(atPath: output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ProbeError.missingTool
            }

            if mode == "post-action" {
                try BackgroundProcessRunner().runInBackground(
                    [CommandLine.arguments[0], "worker", outputDirectory.path],
                    environment: ProcessInfo.processInfo.environment
                )
            }
            try mode.write(to: outputDirectory.appendingPathComponent(mode), atomically: true, encoding: .utf8)
        } catch {
            try String(describing: error).write(
                to: outputDirectory.appendingPathComponent("\(mode).error"), atomically: true, encoding: .utf8
            )
            throw error
        }
    }

    enum ProbeError: Error {
        case parentDidNotExit
        case ignoredChildExitSignal
        case missingTool
    }
}
