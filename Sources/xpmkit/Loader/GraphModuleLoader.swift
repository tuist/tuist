import Basic
import Foundation
import xpmcore

/// Graph module loader error.
///
/// - fileNotFound: thrown when a file included by another Swift file doesn't exist.
/// - fileLoadError: thrown when a file cannot be loaded from disk.
enum GraphModuleLoaderError: FatalError, Equatable {
    case fileNotFound(AbsolutePath)
    case fileLoadError(AbsolutePath, Error)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .fileNotFound:
            return .abort
        case .fileLoadError:
            return .bug
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .fileNotFound(path):
            return "File not found at path \(path.asString)"
        case let .fileLoadError(path, _):
            return "Error loading file at path \(path.asString)"
        }
    }

    /// Returns true if two instances of GraphModuleLoaderError are the same.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
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

/// Interface of a module loader.
protocol GraphModuleLoading: AnyObject {
    /// Given a path, it loads all the paths that should be part of the module.
    /// Any file can include other files in the same module by adding a comment line at
    /// the top:
    ///    //include: ./shared.swift
    /// Notice that the path needs to be relative to the file.
    ///
    /// - Parameter path: path whose module will be loaded.
    /// - Parameter context: context.
    /// - Returns: list of files that should be part of the module.
    func load(_ path: AbsolutePath, context: Contexting) throws -> [AbsolutePath]
}

final class GraphModuleLoader: GraphModuleLoading {
    /// Regular expression used to identify include lines.
    // swiftlint:disable:next force_try
    static let regex = try! NSRegularExpression(pattern: "//\\s*include:\\s+\"?(.+)\"?", options: [])

    /// Given a path, it loads all the paths that should be part of the module.
    /// Any file can include other files in the same module by adding a comment line at
    /// the top:
    ///    //include: ./shared.swift
    /// Notice that the path needs to be relative to the file.
    ///
    /// - Parameter path: path whose module will be loaded.
    /// - Parameter context: context.
    /// - Returns: list of files that should be part of the module.
    func load(_ path: AbsolutePath, context: Contexting) throws -> [AbsolutePath] {
        var paths: [AbsolutePath] = []
        try load(path, paths: &paths, context: context)
        return paths
    }

    /// Recursive method that traverses the module files and adds its paths to the given paths set.
    ///
    /// - Parameters:
    ///   - path: path to be inspected.
    ///   - paths: set that contains the module paths.
    ///   - context: context.
    fileprivate func load(_ path: AbsolutePath, paths: inout [AbsolutePath], context: Contexting) throws {
        if !context.fileHandler.exists(path) {
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
            try load(path.parentDirectory.appending(relativePath),
                     paths: &paths,
                     context: context)
        }
    }
}
