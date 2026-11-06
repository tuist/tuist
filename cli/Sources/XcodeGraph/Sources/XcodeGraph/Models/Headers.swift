import Foundation
import Path

/// Headers
public struct Headers: Equatable, Codable, Sendable {
    /// A Swift package's original header tree. Discovery is retained for hashing and export;
    /// Xcode consumes the tree through include paths and module maps rather than header build files.
    public struct SourceLayout: Equatable, Codable, Sendable {
        public let root: AbsolutePath
        public let publicHeaders: AbsolutePath
        public let moduleMap: AbsolutePath
        public let moduleName: String
        public let usesDirectoryModuleMap: Bool

        public init(
            root: AbsolutePath, publicHeaders: AbsolutePath, moduleMap: AbsolutePath,
            moduleName: String, usesDirectoryModuleMap: Bool
        ) {
            self.root = root
            self.publicHeaders = publicHeaders
            self.moduleMap = moduleMap
            self.moduleName = moduleName
            self.usesDirectoryModuleMap = usesDirectoryModuleMap
        }
    }

    public let sourceLayout: SourceLayout?

    // MARK: - Attributes

    public let `public`: [AbsolutePath]
    public let `private`: [AbsolutePath]
    public let project: [AbsolutePath]

    // MARK: - Init

    public init(
        public: [AbsolutePath],
        private: [AbsolutePath],
        project: [AbsolutePath],
        sourceLayout: SourceLayout? = nil
    ) {
        self.public = `public`
        self.private = `private`
        self.project = project
        self.sourceLayout = sourceLayout
    }

    #if DEBUG
        public static func test(
            public: [AbsolutePath] = [],
            private: [AbsolutePath] = [],
            project: [AbsolutePath] = [],
            sourceLayout: SourceLayout? = nil
        ) -> Headers {
            Headers(
                public: `public`,
                private: `private`,
                project: project,
                sourceLayout: sourceLayout
            )
        }
    #endif
}
