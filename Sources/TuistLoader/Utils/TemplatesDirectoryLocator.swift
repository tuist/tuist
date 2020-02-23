import Basic
import Foundation
import TuistSupport

public protocol TemplatesDirectoryLocating {
    /// Returns the path to the tuist built-in templates directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the templates directory.
    func locate() -> AbsolutePath
    /// Returns the path to the custom templates directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the templates directory.
    func locateCustom(at: AbsolutePath) -> AbsolutePath?
}

public final class TemplatesDirectoryLocator: TemplatesDirectoryLocating {
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
}

