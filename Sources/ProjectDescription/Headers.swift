import Foundation

/// Headers
public struct Headers: Codable, Equatable {

    /// Determine how to resolve intersect cases
    public enum IntersectRule: Int, Codable {
        /// Resolving by manually entered
        /// excluded list in each scope.
        /// Default behaviour
        case none

        /// All subsequent scopes
        /// will exclude file lists of previous scopes.
        case autoExclude
    }

    /// Relative path to public headers.
    public let `public`: FileList?

    /// Relative path to private headers.
    public let `private`: FileList?

    /// Relative path to project headers.
    public let project: FileList?

    // optional, as Codable doesn't support default values
    public let intersectRule: IntersectRule?

    public init(public: FileList? = nil,
                private: FileList? = nil,
                project: FileList? = nil,
                intersectRule: IntersectRule = .none)
    {
        self.public = `public`
        self.private = `private`
        self.project = project
        self.intersectRule = intersectRule
    }
}
