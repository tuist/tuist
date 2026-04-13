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

    /// The HTTP proxy Tuist uses when talking to the Tuist server and related services.
    public enum Proxy: Equatable, Hashable, Sendable {
        /// No proxy. Tuist makes direct connections.
        case none

        /// Read the proxy URL from an environment variable at runtime.
        ///
        /// When `name` is `nil`, Tuist reads `HTTPS_PROXY` and falls back to `HTTP_PROXY`
        /// (both uppercase and lowercase variants are checked).
        case environmentVariable(String?)

        /// Use the given proxy URL directly.
        case url(URL)
    }

    public let project: TuistProject
    public let fullHandle: String?
    public let inspectOptions: InspectOptions
    public let cache: Cache
    public let url: URL
    public let proxy: Proxy

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
        url: URL,
        proxy: Proxy = .none
    ) {
        self.project = project
        self.fullHandle = fullHandle
        self.inspectOptions = inspectOptions
        self.cache = cache
        self.url = url
        self.proxy = proxy
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(project)
        hasher.combine(fullHandle)
        hasher.combine(url)
        hasher.combine(proxy)
    }

    public func assertingIsGeneratedProjectOrSwiftPackage(errorMessageOverride: String?) throws -> Self {
        switch project {
        case .generated, .swiftPackage: return self
        case .xcode: throw TuistConfigError.notAGeneratedProjectNorSwiftPackage(errorMessageOverride: errorMessageOverride)
        }
    }

    #if DEBUG
        public static func test(
            project: TuistProject = .testGeneratedProject(),
            fullHandle: String? = nil,
            inspectOptions: InspectOptions = .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            cache: Cache = Cache(),
            url: URL = Constants.URLs.production,
            proxy: Proxy = .none
        ) -> Self {
            return Tuist(
                project: project,
                fullHandle: fullHandle,
                inspectOptions: inspectOptions,
                cache: cache,
                url: url,
                proxy: proxy
            )
        }
    #endif
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

    #if DEBUG
        public static func test(
            redundantDependencies: RedundantDependencies = .init(ignoreTagsMatching: [])
        ) -> Self {
            return .init(redundantDependencies: redundantDependencies)
        }
    #endif
}
