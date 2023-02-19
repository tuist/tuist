import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol TemplatesDirectoryLocating {
    /// Returns the path to the tuist built-in templates directory if it exists.
    func locateTuistTemplates() -> AbsolutePath?

    /// Returns the path to the user-defined templates directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the templates directory.
    func locateUserTemplates(at: AbsolutePath) -> AbsolutePath?

    /// - Returns: All available directories with defined templates (user-defined and built-in)
    func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath]

    /// - Parameter path: The path to the `Templates` directory for a plugin.
    /// - Returns: All available directories defined for the plugin at the given path
    func templatePluginDirectories(at path: AbsolutePath) throws -> [AbsolutePath]
}

public final class TemplatesDirectoryLocator: TemplatesDirectoryLocating {
    private let rootDirectoryLocator: RootDirectoryLocating

    /// Default constructor.
    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    // MARK: - TemplatesDirectoryLocating

    public func locateTuistTemplates() -> AbsolutePath? {
        #if DEBUG
            // Used only for debug purposes to find templates in your tuist working directory
            // `bundlePath` points to tuist/Templates
            let maybeBundlePath = try? AbsolutePath(validating: #file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
        #else
            let maybeBundlePath = try? AbsolutePath(validating: Bundle(for: TemplatesDirectoryLocator.self).bundleURL.path)
        #endif
        guard let bundlePath = maybeBundlePath else { return nil }
        let paths = [
            bundlePath,
            bundlePath.parentDirectory,
        ]
        let candidates = paths.map { path in
            path.appending(component: Constants.templatesDirectoryName)
        }
        return candidates.first(where: FileHandler.shared.exists)
    }

    public func locateUserTemplates(at: AbsolutePath) -> AbsolutePath? {
        guard let customTemplatesDirectory = locate(from: at) else { return nil }
        if !FileHandler.shared.exists(customTemplatesDirectory) { return nil }
        return customTemplatesDirectory
    }

    public func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath] {
        let tuistTemplatesDirectory = locateTuistTemplates()
        let tuistTemplates = try tuistTemplatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        let userTemplatesDirectory = locateUserTemplates(at: path)
        let userTemplates = try userTemplatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        return (tuistTemplates + userTemplates).filter(FileHandler.shared.isFolder)
    }

    public func templatePluginDirectories(at path: AbsolutePath) throws -> [AbsolutePath] {
        try FileHandler.shared.contentsOfDirectory(path).filter(FileHandler.shared.isFolder)
    }

    // MARK: - Helpers

    private func locate(from path: AbsolutePath) -> AbsolutePath? {
        guard let rootDirectory = rootDirectoryLocator.locate(from: path) else { return nil }
        return rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.templatesDirectoryName)
    }
}
