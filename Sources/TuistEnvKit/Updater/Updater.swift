import Foundation
import RxBlocking
import TuistSupport

protocol Updating: AnyObject {
    func update(force: Bool) throws
}

final class Updater: Updating {
    // MARK: - Attributes

    let githubClient: GitHubClienting
    let versionsController: VersionsControlling
    let googleCloudStorageClient: GoogleCloudStorageClienting
    let installer: Installing
    let envUpdater: EnvUpdating

    // MARK: - Init

    init(githubClient: GitHubClienting = GitHubClient(),
         versionsController: VersionsControlling = VersionsController(),
         installer: Installing = Installer(),
         envUpdater: EnvUpdating = EnvUpdater(),
         googleCloudStorageClient: GoogleCloudStorageClienting = GoogleCloudStorageClient()) {
        self.githubClient = githubClient
        self.versionsController = versionsController
        self.installer = installer
        self.envUpdater = envUpdater
        self.googleCloudStorageClient = googleCloudStorageClient
    }

    // MARK: - Internal

    func update(force: Bool) throws {
        let releases = try githubClient.releases()

        defer {
            try? self.envUpdater.update()
        }

        guard let highestRemoteVersion = try googleCloudStorageClient.latestVersion().toBlocking().first() else {
            Printer.shared.print("No remote versions found")
            return
        }

        if force {
            Printer.shared.print("Forcing the update of version \(highestRemoteVersion)")
            try installer.install(version: highestRemoteVersion.description, force: true)
        } else if let highestLocalVersion = versionsController.semverVersions().sorted().last {
            if highestRemoteVersion <= highestLocalVersion {
                Printer.shared.print("There are no updates available")
            } else {
                Printer.shared.print("Installing new version available \(highestRemoteVersion)")
                try installer.install(version: highestRemoteVersion.description, force: false)
            }
        } else {
            Printer.shared.print("No local versions available. Installing the latest version \(highestRemoteVersion)")
            try installer.install(version: highestRemoteVersion.description, force: false)
        }
    }
}
