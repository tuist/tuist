import Basic
import Foundation
import TuistSupport
import TuistCore

public protocol TemplatesDirectoryLocating {
    /// Returns the path to the custom templates directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the templates directory.
    func locateCustom(at: AbsolutePath) -> AbsolutePath?
    /// - Returns: All available directories with defined templates (custom and built-in)
    func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath]
}

public final class TemplatesDirectoryLocator: TemplatesDirectoryLocating {

    /// Default constructor.
    public init() { }

    // MARK: - TemplatesDirectoryLocating

    public func locateCustom(at: AbsolutePath) -> AbsolutePath? {
        guard let customTemplatesDirectory = locate(from: at) else { return nil }
        if !FileHandler.shared.exists(customTemplatesDirectory) { return nil }
        return customTemplatesDirectory
    }

    public func templateDirectories(at path: AbsolutePath) throws -> [AbsolutePath] {
        let customTemplatesDirectory = locateCustom(at: path)
        let customTemplates = try customTemplatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        return customTemplates.filter(FileHandler.shared.isFolder)
    }

    // MARK: - Helpers

    private func locate(from path: AbsolutePath) -> AbsolutePath? {
        guard let rootDirectory = RootDirectoryLocator.shared.locate(from: path) else { return nil }
        return rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.templatesDirectoryName)
    }
}
