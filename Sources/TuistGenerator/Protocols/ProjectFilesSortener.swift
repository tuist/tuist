import Basic
import Foundation
import TuistCore

/// Protocol that defines the interface of a utility to sort the files before adding them to a project
protocol ProjectFilesSortening {
    /// Sorting function that sorts the files and folders before
    /// adding them to the project.
    ///
    /// - Parameters:
    ///   - lhs: First path to be sorted.
    ///   - rhs: Second path to be sorted.
    /// - Returns: True if the element with the first path should be sorted before the second.
    func sort(lhs: AbsolutePath, rhs: AbsolutePath) -> Bool
}

class ProjectFilesSortener: ProjectFilesSortening {
    /// Instance to interact with the file system.
    private let fileHandler: FileHandling

    /// Lazily filled hash whose keys are paths and the values booleans
    /// indiocating whether the path is a directory or not.
    private var isDirectory: [AbsolutePath: Bool] = [:]

    /// Initializes the sortener with its attributes.
    ///
    /// - Parameter fileHandler: Instance to interact with the file syste.
    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    /// Sorting function that sorts the files and folders before
    /// adding them to the project.
    ///
    /// - Parameters:
    ///   - lhs: First path to be sorted.
    ///   - rhs: Second path to be sorted.
    /// - Returns: True if the element with the first path should be sorted before the second.
    func sort(lhs: AbsolutePath, rhs: AbsolutePath) -> Bool {
        let decompose: (inout [AbsolutePath], String) -> Void = { $0.append($0.last!.appending(component: $1)) }
        let lhsPathsSet = Set(lhs.components.dropFirst().reduce(into: [AbsolutePath("/")], decompose))
        let rhsPathsSet = Set(rhs.components.dropFirst().reduce(into: [AbsolutePath("/")], decompose))

        let commonPaths = lhsPathsSet.intersection(rhsPathsSet)

        guard let lhsPathFirst = lhsPathsSet.subtracting(commonPaths).sorted().first else { return false }
        guard let rhsPathFirst = rhsPathsSet.subtracting(commonPaths).sorted().first else { return true }

        let lhsIsDirectory = isDirectory(lhsPathFirst)
        let rhsIsDirectory = isDirectory(rhsPathFirst)

        switch (lhsIsDirectory, rhsIsDirectory) {
        case (false, true):
            return true
        case (true, false):
            return false
        case (true, true):
            return lhsPathFirst < rhsPathFirst
        case (false, false):
            return lhsPathFirst < rhsPathFirst
        }
    }

    // MARK: - Fileprivate

    /// Returns true if the path points to a directory.
    ///
    /// - Parameter path: Path to be checked.
    /// - Returns: True if the path points to a directory.
    private func isDirectory(_ path: AbsolutePath) -> Bool {
        if let isPathDirectory = isDirectory[path] {
            return isPathDirectory
        }
        let isPathDirectory = fileHandler.isFolder(path)
        isDirectory[path] = isPathDirectory
        return isPathDirectory
    }
}
