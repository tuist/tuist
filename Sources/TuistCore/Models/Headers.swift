import Basic
import Foundation
import TuistSupport
import XcodeProj

/// Headers
public class Headers: Equatable {
    public static let extensions = Xcode.headersExtensions

    // MARK: - Attributes

    public let `public`: [AbsolutePath]
    public let `private`: [AbsolutePath]
    public let project: [AbsolutePath]

    // MARK: - Init

    public init(public: [AbsolutePath],
                private: [AbsolutePath],
                project: [AbsolutePath]) {
        self.public = `public`
        self.private = `private`
        self.project = project
    }

    // MARK: - Equatable

    public static func == (lhs: Headers, rhs: Headers) -> Bool {
        lhs.public == rhs.public &&
            lhs.private == rhs.private &&
            lhs.project == rhs.project
    }
}
