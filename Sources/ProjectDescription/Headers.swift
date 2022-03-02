import Foundation

/// It represents the target headers.
public struct Headers: Codable, Equatable {
    /// Determine how to resolve cases, when the same files found in different header scopes
    public enum AutomaticExclusionRule: Int, Codable {
        /// Project headers = all found - private headers - public headers
        ///
        /// Order of tuist search:
        ///  1) Public headers
        ///  2) Private headers (with auto excludes all found public headers)
        ///  3) Project headers (with excluding public/private headers)
        ///
        ///  Also tuist doesn't ignore all excludes,
        ///  which had been set by `excluding` param
        case projectExcludesPrivateAndPublic

        /// Public headers = all found - private headers - project headers
        ///
        /// Order of tuist search (reverse search):
        ///  1) Project headers
        ///  2) Private headers (with auto excludes all found project headers)
        ///  3) Public headers (with excluding project/private headers)
        ///
        ///  Also tuist doesn't ignore all excludes,
        ///  which had been set by `excluding` param
        case publicExcludesPrivateAndProject
    }

    /// Path to an umbrella header, which will be used to get list of public headers.
    public let umbrellaHeader: Path?

    /// Relative glob pattern that points to the public headers.
    public let `public`: FileList?

    /// Relative glob pattern that points to the private headers.
    public let `private`: FileList?

    /// Relative glob pattern that points to the project headers.
    public let project: FileList?

    /// Rule, which determines how to resolve found duplicates in public/private/project scopes
    public let exclusionRule: AutomaticExclusionRule

    private init(
        public publicHeaders: FileList? = nil,
        umbrellaHeader: Path? = nil,
        private privateHeaders: FileList? = nil,
        project: FileList? = nil,
        exclusionRule: AutomaticExclusionRule
    ) {
        self.public = publicHeaders
        self.umbrellaHeader = umbrellaHeader
        self.private = privateHeaders
        self.project = project
        self.exclusionRule = exclusionRule
    }

    public static func headers(
        public: FileList? = nil,
        private: FileList? = nil,
        project: FileList? = nil,
        exclusionRule: AutomaticExclusionRule = .projectExcludesPrivateAndPublic
    ) -> Headers {
        .init(
            public: `public`,
            private: `private`,
            project: project,
            exclusionRule: exclusionRule
        )
    }

    private static func headers(
        from list: FileList,
        umbrella: Path,
        private privateHeaders: FileList? = nil,
        allOthersAsProject: Bool
    ) -> Headers {
        .init(
            public: list,
            umbrellaHeader: umbrella,
            private: privateHeaders,
            project: allOthersAsProject ? list : nil,
            exclusionRule: .projectExcludesPrivateAndPublic
        )
    }

    /// Headers from the file list are included as:
    /// - `public`, if the header is present in the umbrella header
    /// - `private`, if the header is present in the `private` list
    /// - `project`, otherwise
    /// - Parameters:
    ///     - from: File list, which contains `public` and `project` headers
    ///     - umbrella: File path to the umbrella header
    ///     - private: File list, which contains `private` headers
    public static func allHeaders(
        from list: FileList,
        umbrella: Path,
        private privateHeaders: FileList? = nil
    ) -> Headers {
        headers(
            from: list,
            umbrella: umbrella,
            private: privateHeaders,
            allOthersAsProject: true
        )
    }

    /// Headers from the file list are included as:
    /// - `public`, if the header is present in the umbrella header
    /// - `private`, if the header is present in the `private` list
    /// - not included, otherwise
    /// - Parameters:
    ///     - from: File list, which contains `public` and `project` headers
    ///     - umbrella: File path to the umbrella header
    ///     - private: File list, which contains `private` headers
    public static func onlyHeaders(
        from list: FileList,
        umbrella: Path,
        private privateHeaders: FileList? = nil
    ) -> Headers {
        headers(
            from: list,
            umbrella: umbrella,
            private: privateHeaders,
            allOthersAsProject: false
        )
    }
}
