import Basic
import Foundation
import xpmcore

enum GraphModuleLoaderError: FatalError, Equatable {
    case fileNotFound(AbsolutePath)
    case fileLoadError(AbsolutePath, Error)

    var type: ErrorType {
        switch self {
        case .fileNotFound:
            return .abort
        case .fileLoadError:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .fileNotFound(path):
            return "File not found at path \(path.asString)"
        case let .fileLoadError(path, _):
            return "Error loading file at path \(path.asString)"
        }
    }

    // MARK: - Equatable

    static func == (lhs: GraphModuleLoaderError, rhs: GraphModuleLoaderError) -> Bool {
        switch (lhs, rhs) {
        case let (.fileNotFound(lhsPath), .fileNotFound(rhsPath)):
            return lhsPath == rhsPath
        case let (.fileLoadError(lhsPath, _), .fileLoadError(rhsPath, _)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}

protocol GraphModuleLoading: AnyObject {
    func load(_ path: AbsolutePath) throws -> [AbsolutePath]
}

final class GraphModuleLoader: GraphModuleLoading {
    // swiftlint:disable:next force_try
    static let regex = try! NSRegularExpression(pattern: "//\\s*include:\\s+\"?(.+)\"?", options: [])

    // MARK: - Attributes

    private let fileHandler: FileHandling

    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    // MARK: - GraphModuleLoading

    func load(_ path: AbsolutePath) throws -> [AbsolutePath] {
        var paths: [AbsolutePath] = []
        try load(path, paths: &paths)
        return paths
    }

    // MARK: - Fileprivate

    fileprivate func load(_ path: AbsolutePath, paths: inout [AbsolutePath]) throws {
        if !fileHandler.exists(path) {
            throw GraphModuleLoaderError.fileNotFound(path)
        }
        if paths.contains(path) { return }
        paths.append(path)
        var content: String!
        do {
            content = try String(contentsOf: URL(fileURLWithPath: path.asString))
        } catch {
            throw GraphModuleLoaderError.fileLoadError(path, error)
        }
        let range = NSRange(location: 0, length: content.count)
        let matches = GraphModuleLoader.regex.matches(in: content, options: [], range: range)
        try matches.forEach { match in
            let matchRange = match.range(at: 1)
            let relativePath = RelativePath((content as NSString).substring(with: matchRange))
            try load(path.parentDirectory.appending(relativePath), paths: &paths)
        }
    }
}
