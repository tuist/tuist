import Foundation
import Path
import TuistSupport
import XcodeGraph

public enum TuistConfigError: LocalizedError, Equatable {
    case notAGeneratedProjectNorSwiftPackage(errorMessageOverride: String?)

    public var errorDescription: String? {
        switch self {
        case let .notAGeneratedProjectNorSwiftPackage(errorMessageOverride):
            return errorMessageOverride ?? "A generated Xcode project or Swift Package is necessary for this feature."
        }
    }
}

/// This model allows to configure Tuist.
public struct Tuist: Equatable, Hashable, Sendable {
    /// Configures the project Tuist will interact with.
    /// When no project is provided, Tuist defaults to the workspace or project in the current directory.
    public let project: TuistProject

    /// The full project handle such as "tuist-org/tuist".
    public let fullHandle: String?

    /// The options to use when running `tuist inspect`.
    public let inspectOptions: InspectOptions

    /// The base `URL` that points to the Tuist server.
    public let url: URL

    /// Returns the default Tuist configuration.
    public static var `default`: Tuist {
        return Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: nil,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: Constants.URLs.production
        )
    }

    /// Initializes the tuist configuration.
    ///
    /// - Parameters:
    ///   - project: The `TuistProject` instance that represents the project Tuist will interact with.
    ///   - fullHandle: An optional string representing the full handle of the project, such as "tuist-org/tuist".
    ///   - inspectOptions: The options to use when running `tuist inspect`.
    ///   - url: The base `URL` pointing to the Tuist server.
    public init(
        project: TuistProject,
        fullHandle: String?,
        inspectOptions: InspectOptions,
        url: URL
    ) {
        self.project = project
        self.fullHandle = fullHandle
        self.inspectOptions = inspectOptions
        self.url = url
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(project)
        hasher.combine(fullHandle)
        hasher.combine(url)
    }

    public func assertingIsGeneratedProjectOrSwiftPackage(errorMessageOverride: String?) throws -> Self {
        switch project {
        case .generated, .swiftPackage: return self
        case .xcode: throw TuistConfigError.notAGeneratedProjectNorSwiftPackage(errorMessageOverride: errorMessageOverride)
        }
    }
}

public struct InspectOptions: Codable, Equatable, Hashable, Sendable {
    public struct RedundantDependencies: Codable, Equatable, Hashable, Sendable {
        public let ignoreTagsMatching: Set<String>

        public init(
            ignoreTagsMatching: Set<String>
        ) {
            self.ignoreTagsMatching = ignoreTagsMatching
        }
    }

    public var redundantDependencies: RedundantDependencies

    public init(
        redundantDependencies: RedundantDependencies
    ) {
        self.redundantDependencies = redundantDependencies
    }
}

#if DEBUG
    extension Tuist {
        public static func test(
            project: TuistProject = .testGeneratedProject(),
            fullHandle: String? = nil,
            inspectOptions: InspectOptions = .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: URL = Constants.URLs.production
        ) -> Self {
            return Tuist(project: project, fullHandle: fullHandle, inspectOptions: inspectOptions, url: url)
        }
    }

    extension InspectOptions {
        public static func test(
            redundantDependencies: RedundantDependencies = .init(ignoreTagsMatching: [])
        ) -> Self {
            return .init(redundantDependencies: redundantDependencies)
        }
    }
#endif
