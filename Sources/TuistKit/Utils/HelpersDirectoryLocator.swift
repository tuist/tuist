import Basic
import Foundation
import TuistSupport

protocol HelpersDirectoryLocating {
    /// Returns the path to the helpers directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the helpers directory.
    func locate(at: AbsolutePath) -> AbsolutePath?
}

final class HelpersDirectoryLocator: HelpersDirectoryLocating {
    /// Instance to locate the root directory of the project.
    let rootDirectoryLocator: RootDirectoryLocating

    /// Initializes the locator with its dependencies.
    /// - Parameter rootDirectoryLocator: Instance to locate the root directory of the project.
    init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator.shared) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    // MARK: - HelpersDirectoryLocating

    func locate(at: AbsolutePath) -> AbsolutePath? {
        guard let rootDirectory = self.rootDirectoryLocator.locate(from: at) else { return nil }
        let helpersDirectory = rootDirectory
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.helpersDirectoryName)
        if !FileHandler.shared.exists(helpersDirectory) { return nil }
        return helpersDirectory
    }
}
