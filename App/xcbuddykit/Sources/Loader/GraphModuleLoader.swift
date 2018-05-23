import Basic
import Foundation

enum GraphModuleLoaderError: FatalError {
    case fileNotFound(AbsolutePath)
    case fileLoadError(AbsolutePath, Error)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .fileNotFound:
            return .abort
        case .fileLoadError:
            return .bugSilent
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .fileNotFound(path):
            return "Couldn't file file at path \(path)"
        case let .fileLoadError(path):
            return "Error loading file at path \(path)"
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
    func load(_ path: AbsolutePath, context: Contexting) throws -> Set<AbsolutePath>
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
    /// TODO: Detect circular dependencies
    ///
    /// - Parameter path: path whose module will be loaded.
    /// - Parameter context: context.
    /// - Returns: list of files that should be part of the module.
    func load(_ path: AbsolutePath, context: Contexting) throws -> Set<AbsolutePath> {
        var paths = Set<AbsolutePath>()
        if !context.fileHandler.exists(path) {
            throw GraphModuleLoaderError.fileNotFound(path)
        }
        paths.insert(path)
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
            paths.formUnion(try load(path.parentDirectory.appending(relativePath),
                                     context: context))
        }
        return paths
    }
}
