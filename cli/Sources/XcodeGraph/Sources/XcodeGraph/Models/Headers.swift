import Foundation
import Path

/// Headers
public struct Headers: Equatable, Codable, Sendable {
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

#if DEBUG
    extension Headers {
        public static func test(
            public: [AbsolutePath] = [],
            private: [AbsolutePath] = [],
            project: [AbsolutePath] = []
        ) -> Headers {
            Headers(
                public: `public`,
                private: `private`,
                project: project
            )
        }
    }
#endif
