import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol HelpersDirectoryLocating {
    /// Returns the path to the project description helpers directory if it exists.
    /// - Parameter at: Path from which we traverse the hierarchy to obtain the helpers directory.
    func locateProjectDescriptionHelpers(at: AbsolutePath) -> AbsolutePath?
    
    /// Returns the path to the project automation helpers directory if it exists
    /// - Parameters:
    ///     - at: Path from which we traverse the hieararchy to obtain the helpers directory
    func locateProjectAutomationHelpers(
        at: AbsolutePath
    ) -> AbsolutePath?
}

public final class HelpersDirectoryLocator: HelpersDirectoryLocating {
    /// Instance to locate the root directory of the project.
    let rootDirectoryLocator: RootDirectoryLocating

    /// Default constructor.
    public convenience init() {
        self.init(rootDirectoryLocator: RootDirectoryLocator())
    }

    /// Initializes the locator with its dependencies.
    /// - Parameter rootDirectoryLocator: Instance to locate the root directory of the project.
    init(rootDirectoryLocator: RootDirectoryLocating) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    // MARK: - HelpersDirectoryLocating

    public func locateProjectDescriptionHelpers(at: AbsolutePath) -> AbsolutePath? {
        locateHelpersDirectory(
            at: at,
            directoryName: Constants.projectDescriptionHelpersDirectoryName
        )
    }
    
    public func locateProjectAutomationHelpers(
        at: AbsolutePath
    ) -> AbsolutePath? {
        locateHelpersDirectory(
            at: at,
            directoryName: Constants.projectAutomationHelpersDirectoryName
        )
    }
    
    // MARK: - Helpers
    
    private func locateHelpersDirectory(
        at: AbsolutePath,
        directoryName: String
    ) -> AbsolutePath? {
        guard let rootDirectory = rootDirectoryLocator.locate(from: at) else { return nil }
        let helpersDirectory = rootDirectory
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: directoryName)
        if !FileHandler.shared.exists(helpersDirectory) { return nil }
        return helpersDirectory
    }
}
