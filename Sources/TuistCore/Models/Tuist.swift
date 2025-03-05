import Foundation
import Path
import TuistSupport
import XcodeGraph

/// This model allows to configure Tuist.
public struct Tuist: Equatable, Hashable {
    /// Configures the project Tuist will interact with.
    /// When no project is provided, Tuist defaults to the workspace or project in the current directory.
    public let project: TuistProject

    /// The full project handle such as tuist-org/tuist.
    public let fullHandle: String?

    /// The base URL that points to the Tuist server.
    public let url: URL

    /// Returns the default Tuist configuration.
    public static var `default`: Tuist {
        return Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: nil,
            url: Constants.URLs.production
        )
    }

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:

    public init(
        project: TuistProject,
        fullHandle: String?,
        url: URL
    ) {
        self.project = project
        self.fullHandle = fullHandle
        self.url = url
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(project)
        hasher.combine(fullHandle)
        hasher.combine(url)
    }
}

#if DEBUG
    extension Tuist {
        public static func test(
            project: TuistProject = .testGeneratedProject(),
            fullHandle: String? = nil,
            url: URL = Constants.URLs.production
        ) -> Tuist {
            return Tuist(project: project, fullHandle: fullHandle, url: url)
        }
    }
#endif
