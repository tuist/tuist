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
    private let fileHandler: FileHandling

    // MARK: - Init

    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    // MARK: - ResourceLocating

    func projectDescription() throws -> AbsolutePath {
        return try frameworkPath("ProjectDescription")
    }

    func cliPath() throws -> AbsolutePath {
        return try toolPath("tuist")
    }

    // MARK: - Fileprivate

    fileprivate func frameworkPath(_ name: String) throws -> AbsolutePath {
        let frameworkNames = ["\(name).framework", "lib\(name).dylib"]
        let bundlePath = AbsolutePath(Bundle(for: GraphManifestLoader.self).bundleURL.path)
        let paths = [bundlePath, bundlePath.parentDirectory]
        let candidates = paths.flatMap { path in
            frameworkNames.map { path.appending(component: $0) }
        }
        guard let frameworkPath = candidates.first(where: { fileHandler.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return frameworkPath
    }

    fileprivate func toolPath(_ name: String) throws -> AbsolutePath {
        let bundlePath = AbsolutePath(Bundle(for: GraphManifestLoader.self).bundleURL.path)
        let paths = [bundlePath, bundlePath.parentDirectory]
        let candidates = paths.map { $0.appending(component: name) }
        guard let path = candidates.first(where: { fileHandler.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return path
    }
}
