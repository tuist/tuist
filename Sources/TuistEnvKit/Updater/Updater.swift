import Foundation
import TuistCore

protocol Updating: AnyObject {
    func update(force: Bool) throws
}

final class Updater: Updating {
    // MARK: - Attributes

    let githubClient: GitHubClienting
    let versionsController: VersionsControlling
    let installer: Installing
    let printer: Printing

    // MARK: - Init

    init(githubClient: GitHubClienting = GitHubClient(),
         versionsController: VersionsControlling = VersionsController(),
         installer: Installing = Installer(),
         printer: Printing = Printer()) {
        self.githubClient = githubClient
        self.versionsController = versionsController
        self.installer = installer
        self.printer = printer
    }

    // MARK: - Internal

    func update(force _: Bool) throws {
        let releases = try githubClient.releases()

        guard let highestRemoteVersion = releases.map({ $0.version }).sorted().last else {
            printer.print("No remote versions found")
            return
        }

        if force {
            printer.print("Forcing the update of version \(highestRemoteVersion)")
            try installer.install(version: highestRemoteVersion.description, force: true)
        } else if let highestLocalVersion = versionsController.semverVersions().sorted().last {
            if highestRemoteVersion <= highestLocalVersion {
                printer.print("There are no updates available")
            } else {
                printer.print("Installing new version available \(highestRemoteVersion)")
                try installer.install(version: highestRemoteVersion.description, force: false)
            }
        } else {
            printer.print("No local versions available. Installing the latest version \(highestRemoteVersion)")
            try installer.install(version: highestRemoteVersion.description, force: false)
        }
    }
}
