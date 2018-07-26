import Foundation

/// Headers
public class Headers: Codable {
    /// Relative path to public headers.
    let `public`: String?

    /// Relative path to private headers.
    let `private`: String?

    /// Relative path to project headers.
    let project: String?

    public init(public: String? = nil,
                private: String? = nil,
                project: String? = nil) {
        self.public = `public`
        self.private = `private`
        self.project = project
    }
}
