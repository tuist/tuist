import Foundation
import TuistCore

protocol Updating: AnyObject {
    func update() throws
}

final class Updater: Updating {

    // MARK: - Attributes

    let githubClient: GitHubClienting
    let githubRequestFactory: GitHubRequestsFactory = GitHubRequestsFactory()
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

    func update() throws {
        let json = try githubClient.execute(request: githubRequestFactory.releases())
        let jsonDecoder = JSONDecoder()
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])

        let releases: [Release] = try jsonDecoder.decode([Release].self, from: jsonData)

        guard let highestRemoteVersion = releases.map({ $0.version }).sorted().last else {
            print("No remote versions found")
            return
        }

        if let highestLocalVersion = versionsController.semverVersions().sorted().last {
            if highestRemoteVersion <= highestLocalVersion {
                printer.print("There are no updates available")
            } else {
                printer.print("Installing new version available \(highestRemoteVersion)")
                try installer.install(version: highestRemoteVersion.description)
            }
        } else {
            printer.print("No local versions available. Installing the latest version \(highestRemoteVersion)")
            try installer.install(version: highestRemoteVersion.description)
        }
    }
}
