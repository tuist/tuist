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
        public let caCertificate: String?

        public init(proxy: Bool = true, caCertificate: String? = nil) {
            self.proxy = proxy
            self.caCertificate = caCertificate
        }
    }

    public struct XcodeCache: Equatable, Hashable, Sendable {
        public let upload: Bool
        /// In bytes. `nil` leaves the project's compilation cache stores unpruned.
        public let storeSizeLimit: Int?

        public init(upload: Bool = true, storeSizeLimit: Int? = nil) {
            self.upload = upload
            self.storeSizeLimit = storeSizeLimit
        }
    }

    public struct TestInsights: Equatable, Hashable, Sendable {
        public struct Coverage: Equatable, Hashable, Sendable {
            public let upload: Bool

            public init(upload: Bool = true) {
                self.upload = upload
            }
        }

        public let coverage: Coverage

        public init(coverage: Coverage = Coverage()) {
            self.coverage = coverage
        }
    }

    public let project: TuistProject
    public let fullHandle: String?
    public let inspectOptions: InspectOptions
    public let network: Network
    public let xcodeCache: XcodeCache
    public let testInsights: TestInsights
    public let url: URL

    public static var `default`: Tuist {
        return Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: nil,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            xcodeCache: XcodeCache(),
            url: Constants.URLs.production,
            network: Network()
        )
    }

    public init(
        project: TuistProject,
        fullHandle: String?,
        inspectOptions: InspectOptions,
        xcodeCache: XcodeCache = XcodeCache(),
        testInsights: TestInsights = TestInsights(),
        url: URL,
        network: Network = Network()
    ) {
        self.project = project
        self.fullHandle = fullHandle
        self.inspectOptions = inspectOptions
        self.network = network
        self.xcodeCache = xcodeCache
        self.testInsights = testInsights
        self.url = url
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(project)
        hasher.combine(fullHandle)
        hasher.combine(network)
        hasher.combine(url)
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
            testInsights: TestInsights = TestInsights(),
            url: URL = Constants.URLs.production,
            network: Network = Network()
        ) -> Self {
            return Tuist(
                project: project,
                fullHandle: fullHandle,
                inspectOptions: inspectOptions,
                xcodeCache: xcodeCache,
                testInsights: testInsights,
                url: url,
                network: network
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
