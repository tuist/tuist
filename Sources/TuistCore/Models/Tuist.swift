import Foundation
import Path
import TuistSupport
import XcodeGraph

public enum TuistConfigError: LocalizedError, Equatable {
    case notAGeneratedProject(errorMessageOverride: String?)

    public var errorDescription: String? {
        switch self {
        case let .notAGeneratedProject(errorMessageOverride):
            return errorMessageOverride ?? "A generated Xcode project is necessary for this feature."
        }
    }
}

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

    public func assertingIsGenerated(errorMessageOverride: String?) throws -> Self {
        if !project.isGenerated {
            throw TuistConfigError.notAGeneratedProject(errorMessageOverride: errorMessageOverride)
        }
        return self
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
