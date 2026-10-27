import Path

/// PBXFileSystemSynchronizedRootGroup have a one-to-many relationship with PBXFileSystemSynchronizedBuildFileExceptionSet
/// through .exceptions. Exceptions are used to exclude files and override conffigurations.
public struct BuildableFolderExceptions: Sendable, Codable, Equatable, Hashable, ExpressibleByArrayLiteral, Sequence {
    /// A list with all the exceptions.
    public var exceptions: [BuildableFolderException]

    /// Create a group of exceptions to exclude files from your group or change the configuration of some of them.
    /// - Parameter exceptions: The list of exceptions.
    /// - Returns: An instance containing all the exceptions.
    public init(arrayLiteral elements: BuildableFolderException...) {
        exceptions = elements
    }

    public init(exceptions: [BuildableFolderException]) {
        self.exceptions = exceptions
    }

    /// Returns an iterator over the contained exceptions.
    public func makeIterator() -> [BuildableFolderException].Iterator {
        exceptions.makeIterator()
    }
}
