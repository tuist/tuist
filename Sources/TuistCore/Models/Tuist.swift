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
            project: TuistProject = .defaultGeneratedProject(),
            fullHandle: String? = nil,
            url: URL = Constants.URLs.production
        ) -> Tuist {
            return Tuist(project: project, fullHandle: fullHandle, url: url)
        }
    }

    extension Tuist.GenerationOptions {
        public static func test(
            resolveDependenciesWithSystemScm: Bool = false,
            disablePackageVersionLocking: Bool = false,
            clonedSourcePackagesDirPath: AbsolutePath? = nil,
            staticSideEffectsWarningTargets: TuistCore.Tuist.GenerationOptions.StaticSideEffectsWarningTargets = .all,
            enforceExplicitDependencies: Bool = false,
            defaultConfiguration: String? = nil,
            optionalAuthentication: Bool = false
        ) -> Self {
            .init(
                resolveDependenciesWithSystemScm: resolveDependenciesWithSystemScm,
                disablePackageVersionLocking: disablePackageVersionLocking,
                clonedSourcePackagesDirPath: clonedSourcePackagesDirPath,
                staticSideEffectsWarningTargets: staticSideEffectsWarningTargets,
                enforceExplicitDependencies: enforceExplicitDependencies,
                defaultConfiguration: defaultConfiguration,
                optionalAuthentication: optionalAuthentication
            )
        }
    }

    extension Tuist.InstallOptions {
        public static func test(
            passthroughSwiftPackageManagerArguments: [String] = []
        ) -> Self {
            .init(
                passthroughSwiftPackageManagerArguments: passthroughSwiftPackageManagerArguments
            )
        }
    }
#endif
