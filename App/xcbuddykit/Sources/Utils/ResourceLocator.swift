import Basic
import Foundation

/// Util to locate resources such es the ProjectDescription.framework or the xcbuddy cli binary.
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
    /// - Returns: path to the xcbuddy CLI.
    /// - Throws: an error if the CLI cannot be found.
    func cliPath() throws -> AbsolutePath

    /// Returns the app bundle.
    ///
    /// - Returns: app bundle
    /// - Throws: an error if the bundle cannot be found.
    func appPath() throws -> AbsolutePath
}

/// Resource locating error.
///
/// - notFound: thrown then the resource cannot be found.
enum ResourceLocatingError: Error, ErrorStringConvertible, Equatable {
    case notFound(String)
    var errorDescription: String {
        switch self {
        case let .notFound(name):
            return "Couldn't find \(name)"
        }
    }

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
        let frameworkName = "ProjectDescription.framework"
        let xcbuddyKitPath = AbsolutePath(Bundle(for: GraphManifestLoader.self).bundleURL.path)
        let parentPath = xcbuddyKitPath.parentDirectory
        let pathInProducts = parentPath.appending(component: frameworkName)
        // Built products directory
        if fileHandler.exists(pathInProducts) {
            return pathInProducts
        }
        // Frameworks directory inside the app bundle.
        let appBundlePath = parentPath.parentDirectory.parentDirectory
        if appBundlePath.extension != ".app" {
            throw ResourceLocatingError.notFound(frameworkName)
        }
        guard let frameworksPath = Bundle(path: appBundlePath.asString)?.privateFrameworksPath else {
            throw ResourceLocatingError.notFound(frameworkName)
        }
        let frameworkPath = AbsolutePath(frameworksPath).appending(component: frameworkName)
        if !fileHandler.exists(frameworkPath) {
            throw ResourceLocatingError.notFound(frameworkName)
        }
        return frameworkPath
    }

    /// Returns the CLI path.
    ///
    /// - Returns: path to the xcbuddy CLI.
    /// - Throws: an error if the CLI cannot be found.
    func cliPath() throws -> AbsolutePath {
        let toolName = "xcbuddy"
        let xcbuddyKitPath = AbsolutePath(Bundle(for: GraphManifestLoader.self).bundleURL.path)
        let parentPath = xcbuddyKitPath.parentDirectory
        let pathInProducts = parentPath.appending(component: toolName)
        // Built products directory
        if fileHandler.exists(pathInProducts) {
            return pathInProducts
        }
        // Frameworks directory inside the app bundle.
        let appBundlePath = parentPath.parentDirectory.parentDirectory
        if appBundlePath.extension != ".app" {
            throw ResourceLocatingError.notFound(toolName)
        }
        guard let frameworksPath = Bundle(path: appBundlePath.asString)?.sharedSupportPath else {
            throw ResourceLocatingError.notFound(toolName)
        }
        let toolPath = AbsolutePath(frameworksPath).appending(component: toolName)
        if !fileHandler.exists(toolPath) {
            throw ResourceLocatingError.notFound(toolName)
        }
        return toolPath
    }

    /// Returns the app bundle.
    ///
    /// - Returns: app bundle
    /// - Throws: an error if the bundle cannot be found.
    func appPath() throws -> AbsolutePath {
        let path = AbsolutePath(Bundle(for: ResourceLocator.self).bundleURL.path)
        let appPath = path.parentDirectory.parentDirectory.parentDirectory
        if appPath.extension == "app" {
            return appPath
        } else {
            throw ResourceLocatingError.notFound("xcbuddy.app")
        }
    }
}
