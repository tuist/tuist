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
    public struct Network: Equatable, Hashable, Sendable {
        public let proxy: Bool

        public init(proxy: Bool = true) {
            self.proxy = proxy
        }
    }

    public struct XcodeCache: Equatable, Hashable, Sendable {
        public let upload: Bool

        public init(upload: Bool = true) {
            self.upload = upload
        }
    }

    public let project: TuistProject
    public let fullHandle: String?
    public let inspectOptions: InspectOptions
    public let network: Network
    public let xcodeCache: XcodeCache
    public let url: URL
    public let manifestEnvironment: [String]

    public static var `default`: Tuist {
        return Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: nil,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            xcodeCache: XcodeCache(),
            url: Constants.URLs.production,
            network: Network(),
            manifestEnvironment: []
        )
    }

    public init(
        project: TuistProject,
        fullHandle: String?,
        inspectOptions: InspectOptions,
        xcodeCache: XcodeCache = XcodeCache(),
        url: URL,
        network: Network = Network(),
        manifestEnvironment: [String] = []
    ) {
        self.project = project
        self.fullHandle = fullHandle
        self.inspectOptions = inspectOptions
        self.network = network
        self.xcodeCache = xcodeCache
        self.url = url
        self.manifestEnvironment = manifestEnvironment
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(project)
        hasher.combine(fullHandle)
        hasher.combine(network)
        hasher.combine(url)
        hasher.combine(manifestEnvironment)
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
            xcodeCache: XcodeCache = XcodeCache(),
            url: URL = Constants.URLs.production,
            network: Network = Network(),
            manifestEnvironment: [String] = []
        ) -> Self {
            return Tuist(
                project: project,
                fullHandle: fullHandle,
                inspectOptions: inspectOptions,
                xcodeCache: xcodeCache,
                url: url,
                network: network,
                manifestEnvironment: manifestEnvironment
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
