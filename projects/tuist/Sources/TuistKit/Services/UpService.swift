import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

final class UpService {
    // MARK: - Attributes

    /// Instance to load the setup manifest and perform the project setup.
    private let setupLoader: SetupLoading

    // MARK: - Init

    init(setupLoader: SetupLoading = SetupLoader()) {
        self.setupLoader = setupLoader
    }

    func run(path: String?) throws {
        let path = self.path(path)
        try setupLoader.meet(at: path)
    }

    // MARK: - Fileprivate

    /// Parses the arguments and returns the path to the directory where
    /// the up command should be ran.
    ///
    /// - Parameter path: The path from parsing the command line arguments.
    /// - Returns: Path to be used for the up command.
    private func path(_ path: String?) -> AbsolutePath {
        guard let path = path else {
            return FileHandler.shared.currentPath
        }
        return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
    }
}
