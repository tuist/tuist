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
        case let .embedded(text, affectsBuiltProduct: affectsBuiltProduct):
            switch affectsBuiltProduct {
            case true:
                return """
                    if [ ! $TUIST_BUILD_FOR_DEVELOPMENT ]; then
                        \(text.spm_chomp().spm_chuzzle() ?? "")
                    fi
                    """
            case false:
                return text.spm_chomp().spm_chuzzle() ?? ""
            }

        case let .scriptPath(path, args: args, affectsBuiltProduct: affectsBuiltProduct):
            switch affectsBuiltProduct {
            case true:
                return """
                    if [ ! $TUIST_BUILD_FOR_DEVELOPMENT ]; then
                      \"$SRCROOT\"/\(path.relative(to: sourceRootPath).pathString) \(args.joined(separator: " "))
                    fi
                    """
            case false:
                return "\"$SRCROOT\"/\(path.relative(to: sourceRootPath).pathString) \(args.joined(separator: " "))"
            }

        case let .tool(tool, args, affectsBuiltProduct: affectsBuiltProduct):
            switch affectsBuiltProduct {
            case true:
                return """
                    if [ ! $TUIST_BUILD_FOR_DEVELOPMENT ]; then
                        \(try "\(System.shared.which(tool).spm_chomp().spm_chuzzle()!) \(args.joined(separator: " "))")
                    fi
                    """
            case false:
                return try "\(System.shared.which(tool).spm_chomp().spm_chuzzle()!) \(args.joined(separator: " "))"
            }
        }
    }
}
