import Foundation
import TSCBasic
import TuistSupport
import XcodeProj

/// Headers
public struct Headers: Equatable {
    public static let extensions = Xcode.headersExtensions

    // MARK: - Attributes

    public let `public`: [AbsolutePath]
    public let `private`: [AbsolutePath]
    public let project: [AbsolutePath]

    // MARK: - Init

    public init(public: [AbsolutePath],
                private: [AbsolutePath],
                project: [AbsolutePath])
    {
        self.public = `public`
        self.private = `private`
        self.project = project
    }
}
