import Foundation
import TSCBasic
import TuistSupport

public protocol ResourceLocating: AnyObject {
    func projectAutomation() throws -> AbsolutePath
    func projectDescription() throws -> AbsolutePath
    func cliPath() throws -> AbsolutePath
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

    static func == (lhs: ResourceLocatingError, rhs: ResourceLocatingError) -> Bool {
        switch (lhs, rhs) {
        case let (.notFound(lhsPath), .notFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

public final class ResourceLocator: ResourceLocating {
    public init() {}

    // MARK: - ResourceLocating

    public func projectAutomation() throws -> AbsolutePath {
        try frameworkPath("ProjectAutomation")
    }

    public func projectDescription() throws -> AbsolutePath {
        try frameworkPath("ProjectDescription")
    }

    public func cliPath() throws -> AbsolutePath {
        try toolPath("tuist")
    }

    // MARK: - Fileprivate

    private func frameworkPath(_ name: String) throws -> AbsolutePath {
        let frameworkNames = ["lib\(name).dylib", "\(name).framework", "PackageFrameworks/\(name).framework"]
        let bundlePath = AbsolutePath(Bundle(for: ManifestLoader.self).bundleURL.path)
        let paths = [
            bundlePath,
            bundlePath.parentDirectory,
        ]
        let candidates = paths.flatMap { path in
            frameworkNames.map { path.appending(RelativePath($0)) }
        }
        guard let frameworkPath = candidates.first(where: { FileHandler.shared.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return frameworkPath
    }

    private func toolPath(_ name: String) throws -> AbsolutePath {
        let bundlePath = AbsolutePath(Bundle(for: ManifestLoader.self).bundleURL.path)
        let paths = [bundlePath, bundlePath.parentDirectory]
        let candidates = paths.map { $0.appending(component: name) }
        guard let path = candidates.first(where: { FileHandler.shared.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return path
    }
}
