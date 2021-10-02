import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

extension TargetScript {
    /// Returns the shell script that should be used in the target build phase.
    ///
    /// - Parameters:
    ///   - sourceRootPath: Path to the directory where the Xcode project is generated.
    /// - Returns: Shell script that should be used in the target build phase.
    /// - Throws: An error if the tool absolute path cannot be obtained.
    public func shellScript(sourceRootPath: AbsolutePath) throws -> String {
        switch script {
        case let .embedded(text):
            return text.spm_chomp().spm_chuzzle() ?? ""

        case let .scriptPath(path, args: args):
            return "\"$SRCROOT\"/\(path.relative(to: sourceRootPath).pathString) \(args.joined(separator: " "))"

        case let .tool(tool, args):
            return try "\(System.shared.which(tool).spm_chomp().spm_chuzzle()!) \(args.joined(separator: " "))"
        }
    }
}
