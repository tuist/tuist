import FileSystem
import Foundation
import Path
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

public protocol HelpersDirectoryLocating {
    /// Returns the path to the helpers directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the helpers directory.
    func locate(at: AbsolutePath) async throws -> AbsolutePath?
}

public final class HelpersDirectoryLocator: HelpersDirectoryLocating {
    /// Instance to locate the root directory of the project.
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming

    /// Default constructor.
    public convenience init() {
        self.init(rootDirectoryLocator: RootDirectoryLocator())
    }

    /// Initializes the locator with its dependencies.
    /// - Parameter rootDirectoryLocator: Instance to locate the root directory of the project.
    init(
        rootDirectoryLocator: RootDirectoryLocating,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileSystem = fileSystem
    }

    // MARK: - HelpersDirectoryLocating

    public func locate(at: AbsolutePath) async throws -> AbsolutePath? {
        guard let rootDirectory = try await rootDirectoryLocator.locate(from: at) else { return nil }
        let helpersDirectory = rootDirectory
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.helpersDirectoryName)
        if try await !fileSystem.exists(helpersDirectory) { return nil }
        return helpersDirectory
    }
}

#if DEBUG
    public final class MockHelpersDirectoryLocator: HelpersDirectoryLocating {
        public var locateStub: AbsolutePath?
        public var locateArgs: [AbsolutePath] = []

        public init() {}

        public func locate(at: AbsolutePath) -> AbsolutePath? {
            locateArgs.append(at)
            return locateStub
        }
    }
#endif
