import Foundation
import TSCBasic
import TuistSupport

/// Protocol that defines the interface to locate the tuist binary in the environment.
protocol BinaryLocating {
    /// Returns the binary that should be used for the copy frameworks build phase.
    ///
    /// - Returns: Binary name or path.
    func copyFrameworksBinary() -> String
}

final class BinaryLocator: BinaryLocating {
    /// Returns the binary that should be used for the copy frameworks build phase.
    ///
    /// - Returns: Binary name or path.
    func copyFrameworksBinary() -> String {
        let debugPathPatterns = [".build/", "DerivedData"]
        if let launchPath = CommandLine.arguments.first, debugPathPatterns.contains(where: { launchPath.contains($0) }) {
            return AbsolutePath(launchPath, relativeTo: FileHandler.shared.currentPath).pathString
        }
        return "tuist"
    }
}
