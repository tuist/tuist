import FileSystem
import Foundation
import ProjectDescription

extension FileSysteming {
    /// Performs a simple check to determine if the provided path is a glob pattern.
    /// This method can be used whether to perform a glob operation, or use path as-is.
    /// - Parameter path: The path to check.
    func isGlobPattern(_ path: Path) -> Bool {
        let pathString = path.pathString
        return pathString.contains { globSpecialCharacters.contains($0) }
    }
}

private let globSpecialCharacters: Set<Character> = ["*", "?", "[", "]", "{", "}"]
