/// PBXFileSystemSynchronizedRootGroup have a one-to-many relationship with PBXFileSystemSynchronizedBuildFileExceptionSet
/// through .exceptions. Exceptions are used to exclude files and override conffigurations.
public struct BuildableFolderExceptions: Sendable, Codable, Equatable, Hashable, ExpressibleByArrayLiteral {
    /// A list with all the exceptions.
    public var exceptions: [BuildableFolderException]

    /// Create a group of exceptions to exclude files from your group or change the configuration of some of them.
    /// - Parameter exceptions: The list of exceptions.
    /// - Returns: An instance containing all the exceptions.
    public init(arrayLiteral elements: BuildableFolderException...) {
        exceptions = elements
    }

    private init(exceptions: [BuildableFolderException]) {
        self.exceptions = exceptions
    }

    /// Creates a new instance of `BuildableFolderExceptions` from an array of exceptions.
    ///
    /// This is useful when constructing the structure programmatically, rather than using array literals.
    ///
    /// - Parameter exceptions: The array of `BuildableFolderException` to include.
    /// - Returns: A `BuildableFolderExceptions` value containing all the provided exceptions.
    public static func exceptions(_ exceptions: [BuildableFolderException]) -> Self {
        return BuildableFolderExceptions(exceptions: exceptions)
    }
}
