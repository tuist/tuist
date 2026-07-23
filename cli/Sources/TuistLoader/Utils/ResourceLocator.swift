import FileSystem
import Foundation
import Path
import TuistEnvironment
import TuistLogging
import TuistSupport

public protocol ResourceLocating {
    func projectDescription() async throws -> AbsolutePath
    func cliPath() async throws -> AbsolutePath
    /// The bundled Xcode compilation-cache CAS plugin (`libtuist_cas_plugin.dylib`),
    /// or `nil` if it is not present (e.g. a build from source without the release
    /// bundle). Honours the `TUIST_CAS_PLUGIN_PATH` override.
    func casPlugin() async throws -> AbsolutePath?
    /// The bundled Xcode compilation-cache proxy binary (`tuist-cas-proxy`), or
    /// `nil` if it is not present. Honours the `TUIST_CAS_PROXY_PATH` override.
    func casProxy() async throws -> AbsolutePath?
}

enum ResourceLocatingError: FatalError {
    case notFound(String)

    var description: String {
        switch self {
        case let .notFound(name):
            return "Couldn't find resource named \(name)"
        }
    }

    var type: ErrorType {
        switch self {
        default:
            return .bug
        }
    }
}

public struct ResourceLocator: ResourceLocating {
    private let fileSystem: FileSysteming

    public init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    // MARK: - ResourceLocating

    public func projectDescription() async throws -> AbsolutePath {
        try await frameworkPath("ProjectDescription")
    }

    public func cliPath() async throws -> AbsolutePath {
        try await toolPath("tuist")
    }

    public func casPlugin() async throws -> AbsolutePath? {
        if let override = Environment.current.variables["TUIST_CAS_PLUGIN_PATH"], !override.isEmpty {
            let path = try AbsolutePath(validating: override)
            return try await fileSystem.exists(path) ? path : nil
        }
        // Shipped in the release bundle next to `tuist` (see mise/tasks/cli/bundle.sh).
        let bundlePath = try AbsolutePath(validating: Bundle(for: ManifestLoader.self).bundleURL.path)
        let candidates = [
            bundlePath,
            bundlePath.parentDirectory,
            bundlePath.parentDirectory.appending(component: "lib"),
        ].map { $0.appending(component: "libtuist_cas_plugin.dylib") }
        return try await candidates.concurrentFilter { try await fileSystem.exists($0) }.first
    }

    public func casProxy() async throws -> AbsolutePath? {
        if let override = Environment.current.variables["TUIST_CAS_PROXY_PATH"], !override.isEmpty {
            let path = try AbsolutePath(validating: override)
            return try await fileSystem.exists(path) ? path : nil
        }
        // Shipped in the release bundle next to `tuist` (see mise/tasks/cli/bundle.sh).
        let bundlePath = try AbsolutePath(validating: Bundle(for: ManifestLoader.self).bundleURL.path)
        let candidates = [
            bundlePath,
            bundlePath.parentDirectory,
            bundlePath.parentDirectory.appending(component: "lib"),
        ].map { $0.appending(component: "tuist-cas-proxy") }
        return try await candidates.concurrentFilter { try await fileSystem.exists($0) }.first
    }

    // MARK: - Fileprivate

    private func frameworkPath(_ name: String) async throws -> AbsolutePath {
        let frameworkNames = ["lib\(name).dylib", "\(name).framework", "PackageFrameworks/\(name).framework"]
        let bundlePath = try AbsolutePath(validating: Bundle(for: ManifestLoader.self).bundleURL.path)

        var paths: [AbsolutePath] = [
            bundlePath,
            bundlePath.parentDirectory,
            // == Homebrew directory structure ==
            // x.y.z/
            //   bin/
            //       tuist
            //   lib/
            //       ProjectDescription.framework
            //       ProjectDescription.framework.dSYM
            bundlePath.parentDirectory.appending(component: "lib"),
        ]
        if let frameworkSearchPaths = Environment.current.variables["TUIST_FRAMEWORK_SEARCH_PATHS"]?
            .components(separatedBy: " ")
            .filter({ !$0.isEmpty })
        {
            paths.append(
                contentsOf: try frameworkSearchPaths.map { try AbsolutePath(validating: $0) }
            )
        }
        let candidates = try paths.flatMap { path in
            try frameworkNames.map { path.appending(try RelativePath(validating: $0)) }
        }
        guard let frameworkPath = try await candidates.concurrentFilter({ try await self.fileSystem.exists($0) }).first else {
            throw ResourceLocatingError.notFound(name)
        }
        return frameworkPath
    }

    private func toolPath(_ name: String) async throws -> AbsolutePath {
        let bundlePath = try AbsolutePath(validating: Bundle(for: ManifestLoader.self).bundleURL.path)
        let paths = [bundlePath, bundlePath.parentDirectory]
        let candidates = paths.map { $0.appending(component: name) }
        guard let path = try await candidates.concurrentFilter({ try await self.fileSystem.exists($0) }).first else {
            throw ResourceLocatingError.notFound(name)
        }
        return path
    }
}

#if DEBUG
    public final class MockResourceLocator: ResourceLocating {
        public var projectDescriptionCount: UInt = 0
        public var projectDescriptionStub: (() throws -> AbsolutePath)?
        public var cliPathCount: UInt = 0
        public var cliPathStub: (() throws -> AbsolutePath)?
        public var embedPathCount: UInt = 0
        public var embedPathStub: (() throws -> AbsolutePath)?

        public init() {}

        public func projectDescription() throws -> AbsolutePath {
            projectDescriptionCount += 1
            return try projectDescriptionStub?() ?? AbsolutePath(validating: "/")
        }

        public func cliPath() throws -> AbsolutePath {
            cliPathCount += 1
            return try cliPathStub?() ?? AbsolutePath(validating: "/")
        }

        public var casPluginCount: UInt = 0
        public var casPluginStub: (() throws -> AbsolutePath?)?
        public func casPlugin() throws -> AbsolutePath? {
            casPluginCount += 1
            return try casPluginStub?()
        }

        public var casProxyCount: UInt = 0
        public var casProxyStub: (() throws -> AbsolutePath?)?
        public func casProxy() throws -> AbsolutePath? {
            casProxyCount += 1
            return try casProxyStub?()
        }

        public func embedPath() throws -> AbsolutePath {
            embedPathCount += 1
            return try embedPathStub?() ?? AbsolutePath(validating: "/")
        }
    }
#endif
