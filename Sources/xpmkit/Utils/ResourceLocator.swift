import Basic
import Foundation

/// Util to locate resources such es the ProjectDescription.framework or the xpm cli binary.
protocol ResourceLocating: AnyObject {
    /// Returns the ProjectDescription.framework path.
    ///
    /// - Parameter context: context.
    /// - Returns: ProjectDescription.framework path.
    /// - Throws: an error if the framework cannot be found.
    func projectDescription() throws -> AbsolutePath

    /// Returns the CLI path.
    ///
    /// - Parameter context: context.
    /// - Returns: path to the xpm CLI.
    /// - Throws: an error if the CLI cannot be found.
    func cliPath() throws -> AbsolutePath

    /// Returns the embed util path.
    ///
    /// - Returns: path to the embed util.
    /// - Throws: an error if embed cannot be found.
    func embedPath() throws -> AbsolutePath
}

/// Resource locating error.
///
/// - notFound: thrown then the resource cannot be found.
enum ResourceLocatingError: FatalError {
    case notFound(String)

    /// Error description.
    var description: String {
        switch self {
        case let .notFound(name):
            return "Couldn't find \(name)"
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        default:
            return .bug
        }
    }

    /// Compares two ResourceLocatingError instances.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: ResourceLocatingError, rhs: ResourceLocatingError) -> Bool {
        switch (lhs, rhs) {
        case let (.notFound(lhsPath), .notFound(rhsPath)):
            return lhsPath == rhsPath
        }
    }
}

/// Resource locator.
final class ResourceLocator: ResourceLocating {
    /// File handler.
    private let fileHandler: FileHandling

    /// Initializes the locator with its attributes.
    ///
    /// - Parameter fileHandler: file handler.
    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    /// Returns the ProjectDescription.framework path.
    ///
    /// - Returns: ProjectDescription.framework path.
    /// - Throws: an error if the framework cannot be found.
    func projectDescription() throws -> AbsolutePath {
        return try frameworkPath("ProjectDescription")
    }

    /// Returns the path of the framework/module with the given name.
    ///
    /// - Parameter name: name of the framework
    /// - Returns: path if the framework exists.
    fileprivate func frameworkPath(_ name: String) throws -> AbsolutePath {
        let frameworkNames = ["\(name).framework", "lib\(name).dylib"]
        let bundlePath = AbsolutePath(Bundle(for: GraphManifestLoader.self).bundleURL.path)
        let paths = [bundlePath, bundlePath.parentDirectory]
        let candidates = paths.flatMap { path in
            frameworkNames.map({ path.appending(component: $0) })
        }
        guard let frameworkPath = candidates.first(where: { fileHandler.exists($0) }) else {
            throw ResourceLocatingError.notFound(name)
        }
        return frameworkPath
    }

    /// Returns the CLI path.
    ///
    /// - Returns: path to the xpm CLI.
    /// - Throws: an error if the CLI cannot be found.
    func cliPath() throws -> AbsolutePath {
        return try toolPath("xpm")
    }

    /// Returns the embed util path.
    ///
    /// - Returns: path to the embed util.
    /// - Throws: an error if embed cannot be found.
    func embedPath() throws -> AbsolutePath {
        return try toolPath("xpmembed")
    }

    /// Returns the path to the tool with the given name.
    /// Command line tools are bundled in the shared support directory of the application bundle.
    /// If the project is executed from Xcode, the tool will be in the built products directory instead.
    ///
    /// - Parameter name: name of the tool.
    /// - Returns: the path to the tool if it could be found.
    /// - Throws: an error if the tool couldn't be found.
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
