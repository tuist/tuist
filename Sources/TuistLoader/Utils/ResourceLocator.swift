import FileSystem
import Foundation
import Path
import TuistSupport

public protocol ResourceLocating: AnyObject {
    func projectDescription() async throws -> AbsolutePath
    func cliPath() async throws -> AbsolutePath
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

public final class ResourceLocator: ResourceLocating {
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

        public func embedPath() throws -> AbsolutePath {
            embedPathCount += 1
            return try embedPathStub?() ?? AbsolutePath(validating: "/")
        }
    }
#endif
