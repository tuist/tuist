import Basic
import Foundation
import TuistLoader
import TuistSupport

public protocol TemplatesDirectoryLocating {
    /// Returns the path to the tuist built-in templates directory if it exists.
    func locate() -> AbsolutePath?
    /// Returns the path to the custom templates directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the templates directory.
    func locateCustom(at: AbsolutePath) -> AbsolutePath?
    /// - Returns: Path of templates directory up the three `from`
    func locate(from path: AbsolutePath) -> AbsolutePath?
    /// - Returns: All available directories with defined templates (custom and built-in)
    func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath]
}

public final class TemplatesDirectoryLocator: TemplatesDirectoryLocating {
    private let rootDirectoryLocator: RootDirectoryLocating

    /// Default constructor.
    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    // MARK: - TemplatesDirectoryLocating

    public func locate() -> AbsolutePath? {
        #if DEBUG
            // Used only for debug purposed to find templates in your tuist working directory
            let bundlePath = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .appending(component: Constants.tuistDirectoryName)
        #else
            let bundlePath = AbsolutePath(Bundle(for: ManifestLoader.self).bundleURL.path)
        #endif
        let paths = [
            bundlePath,
            bundlePath.parentDirectory,
        ]
        let candidates = paths.map { path in
            path.appending(component: Constants.templatesDirectoryName)
        }
        return candidates.first(where: { FileHandler.shared.exists($0) })
    }

    public func locateCustom(at: AbsolutePath) -> AbsolutePath? {
        guard let customTemplatesDirectory = locate(from: at) else { return nil }
        if !FileHandler.shared.exists(customTemplatesDirectory) { return nil }
        return customTemplatesDirectory
    }

    public func locate(from path: AbsolutePath) -> AbsolutePath? {
        guard let rootDirectory = rootDirectoryLocator.locate(from: path) else { return nil }
        return rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.templatesDirectoryName)
    }

    public func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath] {
        let templatesDirectory = locate()
        let templates = try templatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        let customTemplatesDirectory = locateCustom(at: path)
        let customTemplates = try customTemplatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        return (templates + customTemplates).filter(FileHandler.shared.isFolder)
    }
}
