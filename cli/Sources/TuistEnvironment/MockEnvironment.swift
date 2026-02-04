#if DEBUG
    import Foundation
    import Path
    #if canImport(Testing)
        import Testing
    #endif

    /// A mock implementation of Environmenting for testing
    public final class MockEnvironment: Environmenting {
        private let temporaryPath: AbsolutePath

        public init(temporaryDirectory: AbsolutePath? = nil) throws {
            if let temporaryDirectory {
                temporaryPath = temporaryDirectory
            } else {
                let tempDir = FileManager.default.temporaryDirectory
                let uniquePath = tempDir.appendingPathComponent("tuist-test-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: uniquePath, withIntermediateDirectories: true)
                temporaryPath = try AbsolutePath(validating: uniquePath.path)
            }
            stateDirectory = temporaryPath.appending(component: "state")
            cacheDirectory = temporaryPath.appending(component: ".cache")
            homeDirectory = temporaryPath.appending(component: "home")
        }

        public var processId: String = UUID().uuidString
        public var isJSONOutput: Bool = false
        public var isVerbose: Bool = false
        public var queueDirectoryStub: AbsolutePath?
        public var shouldOutputBeColoured: Bool = false
        public var isStandardOutputInteractive: Bool = false
        public var manifestLoadingVariables: [String: String] = [:]
        public var isStatsEnabled: Bool = true
        public var isGitHubActions: Bool = false
        public var variables: [String: String] = [:]
        public var arguments: [String] = []
        public var workspacePath: AbsolutePath?
        public var schemeName: String?
        public var currentExecutablePathStub: AbsolutePath?

        public func currentExecutablePath() -> AbsolutePath? {
            currentExecutablePathStub ?? Environment.currentExecutablePath()
        }

        public var homeDirectory: AbsolutePath

        public func derivedDataDirectory() async throws -> Path.AbsolutePath {
            temporaryPath.appending(component: "DerivedData")
        }

        public var stubbedArchitecture: MacArchitecture = .arm64
        public func architecture() async throws -> MacArchitecture {
            stubbedArchitecture
        }

        public func currentWorkingDirectory() async throws -> AbsolutePath {
            temporaryPath.appending(component: "current")
        }

        public var cacheDirectory: AbsolutePath
        public var stateDirectory: AbsolutePath

        public var configDirectory: AbsolutePath {
            temporaryPath.appending(component: "config")
        }

        public var queueDirectory: AbsolutePath {
            queueDirectoryStub ?? temporaryPath.appending(component: "Queue")
        }

        public func cacheSocketPath(for fullHandle: String) -> AbsolutePath {
            stateDirectory.appending(component: "\(fullHandle.replacingOccurrences(of: "/", with: "_")).sock")
        }

        public func cacheSocketPathString(for fullHandle: String) -> String {
            "$HOME/\(fullHandle).sock"
        }
    }

    extension Environment {
        public static var mocked: MockEnvironment? { current as? MockEnvironment }
    }

    public func withMockedEnvironment(
        temporaryDirectory: AbsolutePath? = nil,
        legacyModuleCache: Bool? = nil,
        _ closure: () async throws -> Void
    ) async throws {
        let mockEnvironment = try MockEnvironment(temporaryDirectory: temporaryDirectory)
        if let legacyModuleCache {
            mockEnvironment.variables["TUIST_LEGACY_MODULE_CACHE"] = legacyModuleCache ? "1" : "0"
        }
        try await Environment.$current.withValue(mockEnvironment) {
            try await closure()
        }
    }

#endif
