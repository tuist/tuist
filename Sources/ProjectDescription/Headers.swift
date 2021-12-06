import Foundation

/// Headers
public struct Headers: Codable, Equatable {

    /// Determine how to resolve intersection cases
    public enum IntersectionRule: Int, Codable {
        /// Resolving by manually entered
        /// excluded list in each scope.
        /// Default behavior
        case none

        /// All subsequent scopes
        /// will exclude file lists from previous scopes.
        case autoExclude
    }

    /// Relative path to public headers.
    public let `public`: FileList?

    /// Relative path to private headers.
    public let `private`: FileList?

    /// Relative path to project headers.
    public let project: FileList?

    // optional, as Codable doesn't support default values
    public let intersectionRule: IntersectionRule?

    public init(public: FileList? = nil,
                private: FileList? = nil,
                project: FileList? = nil,
                intersectionRule: IntersectionRule = .none)
    {
        self.public = `public`
        self.private = `private`
        self.project = project
        self.intersectionRule = intersectionRule
    }
}
