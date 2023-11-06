import Foundation
import TSCUtility
import TuistSupport

final class InstallService {
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
        let parsedVersion = try Version(versionString: version, usesLenientParsing: true)
        let versions = versionsController.versions().map(\.description)
        if versions.contains(parsedVersion.description) {
            WarningController.shared.append(warning: "Version \(parsedVersion) already installed, skipping")
            return
        }
        try installer.install(version: parsedVersion.description)
    }
}
