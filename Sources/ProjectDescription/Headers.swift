import Foundation

/// Headers
public struct Headers: Codable, Equatable {
    /// Relative path to public headers.
    public let `public`: FileList?

    /// Relative path to private headers.
    public let `private`: FileList?

    /// Relative path to project headers.
    public let project: FileList?

    public init(public: FileList? = nil,
                private: FileList? = nil,
                project: FileList? = nil)
    {
        self.public = `public`
        self.private = `private`
        self.project = project
    }
}
