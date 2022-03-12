import Foundation
import TuistSupport

protocol Updating: AnyObject {
    func update() throws
}

final class Updater: Updating {
    // MARK: - Attributes

    let versionsController: VersionsControlling
    let installer: Installing
    let envInstaller: EnvInstalling
    let versionProvider: VersionProviding

    // MARK: - Init

    init(
        versionsController: VersionsControlling = VersionsController(),
        installer: Installing = Installer(),
        envInstaller: EnvInstalling = EnvInstaller(),
        versionProvider: VersionProviding = VersionProvider()
    ) {
        self.versionsController = versionsController
        self.installer = installer
        self.envInstaller = envInstaller
        self.versionProvider = versionProvider
    }

    // MARK: - Internal

    func update() throws {
        guard let highestRemoteVersion = try versionProvider.latestVersion() else {
            logger.warning("No remote versions found")
            return
        }

        if let highestLocalVersion = versionsController.semverVersions().sorted().last {
            guard highestRemoteVersion > highestLocalVersion else {
                logger.notice("There are no updates available")
                return
            }
            logger.notice("Installing new version available \(highestRemoteVersion)")
        } else {
            logger.notice("No local versions available. Installing the latest version \(highestRemoteVersion)")
        }

        try installer.install(version: highestRemoteVersion.description)
        logger.info("Updating tuistenv", metadata: .section)
        try envInstaller.install(version: highestRemoteVersion.description)
    }
}
