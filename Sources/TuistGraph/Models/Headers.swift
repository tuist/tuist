import Foundation
import TSCBasic

/// Headers
public struct Headers: Equatable, Codable {
    // MARK: - Attributes

    public let `public`: [AbsolutePath]
    public let `private`: [AbsolutePath]
    public let project: [AbsolutePath]

    // MARK: - Init

    public init(
        public: [AbsolutePath],
        private: [AbsolutePath],
        project: [AbsolutePath]
    ) {
        self.public = `public`
        self.private = `private`
        self.project = project
    }
}
