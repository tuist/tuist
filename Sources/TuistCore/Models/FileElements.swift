import Basic
import Foundation

public enum FileElements: Equatable {
    case files([AbsolutePath])
    case folderReferences([AbsolutePath])

    public var paths: [AbsolutePath] {
        switch self {
        case let .files(paths):
            return paths
        case let .folderReferences(paths):
            return paths
        }
    }

    public var isReference: Bool {
        switch self {
        case .files:
            return false
        case .folderReferences:
            return true
        }
    }

    /// Returns a copy filtering the paths using the given closure.
    /// - Parameter isIncluded: Returns true for those paths that should be included.
    public func filter(_ isIncluded: (AbsolutePath) -> Bool) -> FileElements {
        switch self {
        case let .files(paths):
            return .files(paths.filter(isIncluded))
        case let .folderReferences(paths):
            return .folderReferences(paths.filter(isIncluded))
        }
    }
}
