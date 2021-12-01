import Foundation
import TuistSupport

final class UninstallService {
    /// Controller to manage system versions.
    private let versionsController: VersionsControlling

    /// Installer instance to run the installation.
    private let installer: Installing

    init(
        versionsController: VersionsControlling = VersionsController(),
        installer: Installing = Installer()
    ) {
        self.versionsController = versionsController
        self.installer = installer
    }

    func run(version: String) throws {
        let versions = versionsController.versions().map(\.description)
        if versions.contains(version) {
            try versionsController.uninstall(version: version)
            logger.notice("Version \(version) uninstalled", metadata: .success)
        } else {
            logger.warning("Version \(version) cannot be uninstalled because it's not installed")
        }
    }
}
