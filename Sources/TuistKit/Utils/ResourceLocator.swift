import Basic
import Foundation
import TuistCore

protocol ResourceLocating: AnyObject {
    func projectDescription() throws -> AbsolutePath
    func cliPath() throws -> AbsolutePath
}

enum ResourceLocatingError: FatalError {
    case notFound(String)

    var description: String {
        switch self {
        case let .notFound(name):
            return "Couldn't find \(name)"
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

final class ResourceLocator: ResourceLocating {
    // MARK: - ResourceLocating

    func projectDescription() throws -> AbsolutePath {
        return try frameworkPath("ProjectDescription")
    }

    func cliPath() throws -> AbsolutePath {
        return try toolPath("tuist")
    }

    // MARK: - Fileprivate

    private func frameworkPath(_ name: String) throws -> AbsolutePath {
        let frameworkNames = ["\(name).framework", "lib\(name).dylib"]
        let bundlePath = AbsolutePath(Bundle(for: GraphManifestLoader.self).bundleURL.path)
        let paths = [
            AbsolutePath("/Users/marekfort/Development/tuist/.build/x86_64-apple-macosx"),
            AbsolutePath("/Users/marekfort/Development/tuist/.build/x86_64-apple-macosx/debug"),
            bundlePath,
            bundlePath.parentDirectory
        ]
        let candidates = paths.flatMap { path in
            frameworkNames.map { path.appending(component: $0) }
        }
        guard let frameworkPath = candidates.first(where: { FileHandler.shared.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return frameworkPath
    }

    private func toolPath(_ name: String) throws -> AbsolutePath {
        let bundlePath = AbsolutePath(Bundle(for: GraphManifestLoader.self).bundleURL.path)
        let paths = [bundlePath, bundlePath.parentDirectory]
        let candidates = paths.map { $0.appending(component: name) }
        guard let path = candidates.first(where: { FileHandler.shared.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return path
    }
}
