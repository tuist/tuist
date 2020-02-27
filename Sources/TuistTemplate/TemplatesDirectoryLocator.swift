import Basic
import Foundation
import TuistSupport
import TuistLoader

public protocol TemplatesDirectoryLocating {
    /// Returns the path to the tuist built-in templates directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the templates directory.
    func locate() -> AbsolutePath
    /// Returns the path to the custom templates directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the templates directory.
    func locateCustom(at: AbsolutePath) -> AbsolutePath?
    func locate(from path: AbsolutePath) -> AbsolutePath?
}

public final class TemplatesDirectoryLocator: TemplatesDirectoryLocating {
    private let fileHandler: FileHandling = FileHandler.shared
    /// This cache avoids having to traverse the directories hierarchy every time the locate method is called.
    private var cache: [AbsolutePath: AbsolutePath] = [:]
    
    /// Instance to locate the root directory of the project.
    let rootDirectoryLocator: RootDirectoryLocating

    /// Default constructor.
    public convenience init() {
        self.init(rootDirectoryLocator: RootDirectoryLocator.shared)
    }

    /// Initializes the locator with its dependencies.
    /// - Parameter rootDirectoryLocator: Instance to locate the root directory of the project.
    init(rootDirectoryLocator: RootDirectoryLocating) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    // MARK: - TemplatesDirectoryLocating

    public func locate() -> AbsolutePath {
        let bundlePath = AbsolutePath(Bundle(for: ManifestLoader.self).bundleURL.path)
        let paths = [
            bundlePath,
            bundlePath.parentDirectory,
        ]
        let candidates = paths.map { path in
            path.appending(component: "Templates")
        }
        guard let templatesPath = candidates.first(where: { FileHandler.shared.exists($0) }) else {
            fatalError()
        }
        return templatesPath
    }
    
    public func locateCustom(at: AbsolutePath) -> AbsolutePath? {
        guard let rootDirectory = rootDirectoryLocator.locate(from: at) else { return nil }
        let customTemplatesDirectory = rootDirectory
            .appending(components: Constants.tuistDirectoryName, Constants.templatesDirectoryName)
        if !FileHandler.shared.exists(customTemplatesDirectory) { return nil }
        return customTemplatesDirectory
    }
    
    public func locate(from path: AbsolutePath) -> AbsolutePath? {
        locate(from: path, source: path)
    }
    
    // MARK: - Helpers
    
    private func locate(from path: AbsolutePath, source: AbsolutePath) -> AbsolutePath? {
        if let cachedDirectory = cached(path: path) {
            return cachedDirectory
        } else if fileHandler.exists(path.appending(RelativePath(Constants.tuistDirectoryName))) {
            cache(rootDirectory: path, for: source)
            return path.appending(component: Constants.templatesDirectoryName)
        } else if fileHandler.exists(path.appending(component: Constants.templatesDirectoryName)) {
            cache(rootDirectory: path.appending(component: Constants.templatesDirectoryName), for: source)
            return path
        } else if fileHandler.exists(path.appending(RelativePath(".git"))) {
            cache(rootDirectory: path, for: source)
            return path
        } else if !path.isRoot {
            return locate(from: path.parentDirectory, source: source)
        }
        return nil
    }
    
    private func cached(path: AbsolutePath) -> AbsolutePath? {
        cache[path]
    }

    /// This method caches the root directory of path, and all its parents up to the root directory.
    /// - Parameters:
    ///   - rootDirectory: Path to the root directory.
    ///   - path: Path for which we are caching the root directory.
    private func cache(rootDirectory: AbsolutePath, for path: AbsolutePath) {
        if path != rootDirectory {
            cache[path] = rootDirectory
            cache(rootDirectory: rootDirectory, for: path.parentDirectory)
        } else if path == rootDirectory {
            cache[path] = rootDirectory
        }
    }
}

