import FileSystem
import Foundation
import Mockable
import Path
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistRootDirectoryLocator
import TuistSupport

@Mockable
public protocol TemplatesDirectoryLocating {
    /// Returns the path to the tuist built-in templates directory if it exists.
    func locateTuistTemplates() async throws -> AbsolutePath?

    /// Returns the path to the user-defined templates directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the templates directory.
    func locateUserTemplates(at: AbsolutePath) async throws -> AbsolutePath?

    /// - Returns: All available directories with defined templates (user-defined and built-in)
    func templateDirectories(at path: AbsolutePath) async throws -> [AbsolutePath]

    /// - Parameter path: The path to the `Templates` directory for a plugin.
    /// - Returns: All available directories defined for the plugin at the given path
    func templatePluginDirectories(at path: AbsolutePath) async throws -> [AbsolutePath]
}

public final class TemplatesDirectoryLocator: TemplatesDirectoryLocating {
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming

    /// Default constructor.
    public init(
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileSystem = fileSystem
    }

    // MARK: - TemplatesDirectoryLocating

    public func locateTuistTemplates() async throws -> AbsolutePath? {
        #if DEBUG
            let maybeBundlePath: AbsolutePath?
            if let sourceRoot = Environment.current.variables["TUIST_CONFIG_SRCROOT"] {
                maybeBundlePath = try? AbsolutePath(validating: sourceRoot).appending(components: ["cli", "Templates"])
            } else {
                // Used only for debug purposes to find templates in your tuist working directory
                // `bundlePath` points to tuist/Templates
                maybeBundlePath = try? AbsolutePath(validating: #file.replacingOccurrences(of: "file://", with: ""))
                    .removingLastComponent()
                    .removingLastComponent()
                    .removingLastComponent()
            }
        #else
            let maybeBundlePath = try? AbsolutePath(validating: Bundle(for: TemplatesDirectoryLocator.self).bundleURL.path)
        #endif
        guard let bundlePath = maybeBundlePath else { return nil }
        let paths = [
            bundlePath,
            bundlePath.parentDirectory,
            // == Homebrew directory structure ==
            // x.y.z/
            //   bin/
            //       tuist
            //   share/
            //       Templates
            bundlePath.parentDirectory.appending(try! RelativePath(validating: "share")),
            // swiftlint:disable:previous force_try
        ]
        let candidates = paths.map { path in
            path.appending(component: Constants.templatesDirectoryName)
        }
        return try await candidates.concurrentFilter(fileSystem.exists).first
    }

    public func locateUserTemplates(at: AbsolutePath) async throws -> AbsolutePath? {
        guard let customTemplatesDirectory = try await locate(from: at) else { return nil }
        if try await !fileSystem.exists(customTemplatesDirectory) { return nil }
        return customTemplatesDirectory
    }

    public func templateDirectories(at path: AbsolutePath) async throws -> [AbsolutePath] {
        let tuistTemplatesDirectory = try await locateTuistTemplates()
        var tuistTemplates: [AbsolutePath] = []
        if let tuistTemplatesDirectory {
            tuistTemplates = try await fileSystem.contentsOfDirectory(tuistTemplatesDirectory)
        }
        let userTemplatesDirectory = try await locateUserTemplates(at: path)
        var userTemplates: [AbsolutePath] = []
        if let userTemplatesDirectory {
            userTemplates = try await fileSystem.contentsOfDirectory(userTemplatesDirectory)
        }
        var result: [AbsolutePath] = []
        for item in tuistTemplates + userTemplates {
            if try await fileSystem.exists(item, isDirectory: true) {
                result.append(item)
            }
        }
        return result
    }

    public func templatePluginDirectories(at path: AbsolutePath) async throws -> [AbsolutePath] {
        let contents = try await fileSystem.contentsOfDirectory(path)
        var result: [AbsolutePath] = []
        for item in contents {
            if try await fileSystem.exists(item, isDirectory: true) {
                result.append(item)
            }
        }
        return result
    }

    // MARK: - Helpers

    private func locate(from path: AbsolutePath) async throws -> AbsolutePath? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: path) else { return nil }
        return rootDirectory.appending(components: Constants.tuistDirectoryName, Constants.templatesDirectoryName)
    }
}
