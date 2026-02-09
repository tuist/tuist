import Foundation
import TuistConstants

public enum TuistConfigError: LocalizedError, Equatable {
    case notAGeneratedProjectNorSwiftPackage(errorMessageOverride: String?)

    public var errorDescription: String? {
        switch self {
        case let .notAGeneratedProjectNorSwiftPackage(errorMessageOverride):
            return errorMessageOverride ?? "A generated Xcode project or Swift Package is necessary for this feature."
        }
    }
}

public struct Tuist: Equatable, Hashable, Sendable {
    public struct Cache: Equatable, Hashable, Sendable {
        public let upload: Bool

        public init(upload: Bool = true) {
            self.upload = upload
        }
    }

    public let project: TuistProject
    public let fullHandle: String?
    public let inspectOptions: InspectOptions
    public let cache: Cache
    public let url: URL

    public static var `default`: Tuist {
        return Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: nil,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            cache: Cache(),
            url: Constants.URLs.production
        )
    }

    public init(
        project: TuistProject,
        fullHandle: String?,
        inspectOptions: InspectOptions,
        cache: Cache = Cache(),
        url: URL
    ) {
        self.project = project
        self.fullHandle = fullHandle
        self.inspectOptions = inspectOptions
        self.cache = cache
        self.url = url
    }

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
            cache: Cache = Cache(),
            url: URL = Constants.URLs.production
        ) -> Self {
            return Tuist(project: project, fullHandle: fullHandle, inspectOptions: inspectOptions, cache: cache, url: url)
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
