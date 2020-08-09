import Foundation
import TuistSupport

final class InstallService {
    /// Controller to manage system versions.
    private let versionsController: VersionsControlling

    /// Installer instance to run the installation.
    private let installer: Installing

    init(versionsController: VersionsControlling = VersionsController(),
         installer: Installing = Installer())
    {
        self.versionsController = versionsController
        self.installer = installer
    }

    func run(version: String, force: Bool) throws {
        let versions = versionsController.versions().map { $0.description }
        if versions.contains(version) {
            logger.warning("Version \(version) already installed, skipping")
            return
        }
        try installer.install(version: version, force: force)
    }
}
