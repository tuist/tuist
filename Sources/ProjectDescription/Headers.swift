import Foundation

/// Headers
public class Headers: JSONConvertible {
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

    /// Returns a JSON representation of the object.
    ///
    /// - Returns: JSON representation.
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        if let `public` = `public` {
            dictionary["public"] = `public`.toJSON()
        }
        if let `private` = `private` {
            dictionary["private"] = `private`.toJSON()
        }
        if let project = project {
            dictionary["project"] = project.toJSON()
        }
        return JSON.dictionary(dictionary)
    }
}
