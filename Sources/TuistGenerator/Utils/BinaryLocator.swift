import Basic
import Foundation
import TuistCore

/// Protocol that defines the interface to locate the tuist binary in the environment.
protocol BinaryLocating {
    /// Returns the binary that should be used for the copy frameworks build phase.
    ///
    /// - Returns: Binary name or path.
    func copyFrameworksBinary() -> String
}

final class BinaryLocator: BinaryLocating {
    /// Instance to interact with the file system.
    let fileHandler: FileHandling

    /// Initializes the binary locator with its attributes.
    ///
    /// - Parameter fileHandler: File handler instance to interact with the file system.
    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    /// Returns the binary that should be used for the copy frameworks build phase.
    ///
    /// - Returns: Binary name or path.
    func copyFrameworksBinary() -> String {
        let debugPathPatterns = [".build/", "DerivedData"]
        if let launchPath = CommandLine.arguments.first, debugPathPatterns.contains(where: { launchPath.contains($0) }) {
            return AbsolutePath(launchPath, relativeTo: fileHandler.currentPath).pathString
        }
        return "tuist"
    }
}
