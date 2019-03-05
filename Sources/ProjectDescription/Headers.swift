import Foundation

/// Headers
public class Headers: Codable {
    /// Relative path to public headers.
    public let `public`: String?

    /// Relative path to private headers.
    public let `private`: String?

    /// Relative path to project headers.
    public let project: String?

    public init(public: String? = nil,
                private: String? = nil,
                project: String? = nil) {
        self.public = `public`
        self.private = `private`
        self.project = project
    }
}
