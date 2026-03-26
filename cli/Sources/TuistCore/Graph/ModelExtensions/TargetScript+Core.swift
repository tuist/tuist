import Command
import Path
import TuistSupport
import XcodeGraph

extension TargetScript {
    public func shellScript(sourceRootPath: AbsolutePath) async throws -> String {
        switch script {
        case let .embedded(text):
            return text.spm_chomp().spm_chuzzle() ?? ""

        case let .scriptPath(path, args: args):
            return "\"$SRCROOT\"/\(path.relative(to: sourceRootPath).pathString) \(args.joined(separator: " "))"

        case let .tool(tool, args):
            let toolPath = try await CommandRunner()
                .run(arguments: ["/usr/bin/env", "which", tool])
                .concatenatedString()
                .spm_chomp()
                .spm_chuzzle()!
            return "\(toolPath) \(args.joined(separator: " "))"
        }
    }
}
