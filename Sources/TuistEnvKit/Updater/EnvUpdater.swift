import Basic
import Foundation
import TuistCore
import SPMUtility

/// Protocol that defines the interface to update the environment.
protocol EnvUpdating {
    /// Updates the local tuistenv installation.
    ///
    /// - Throws: An error if the installation fails.
    func update() throws
}

final class EnvUpdater: EnvUpdating {
    /// System instance to run commands.
    let system: Systeming

    /// Instance to interact with the file system.
    let fileHandler: FileHandling

    /// GitHub API client.
    let githubClient: GitHubClienting

    /// Initializes the env update with its attributes.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands.
    ///   - fileHandler: Instance to interact with the file system.
    ///   - githubClient: GitHub API client.
    init(system: Systeming = System(),
         fileHandler: FileHandling = FileHandler(),
         githubClient: GitHubClienting = GitHubClient()) {
        self.system = system
        self.fileHandler = fileHandler
        self.githubClient = githubClient
    }

    /// Updates the local tuistenv installation.
    ///
    /// - Throws: An error if the installation fails.
    func update() throws {
        guard let releases: [Release] = try? self.githubClient.releases(),
            let release = releases.sorted(by: { $0.version > $1.version }).first,
            let asset = release.assets.first(where: { $0.name.contains("tuistenv") }) else {
            return
        }

        try fileHandler.inTemporaryDirectory { directory in
            // Download
            let fileName = asset.downloadURL.lastPathComponent
            let downloadPath = directory.appending(component: fileName)
            try system.run("/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, asset.downloadURL.absoluteString)
            try system.run("/usr/bin/unzip", "-o", downloadPath.pathString, "-d", "/tmp/")
            let binaryPath = "/tmp/tuistenv"
            try system.run(["/bin/chmod", "+x", binaryPath])

            // Replace
            try system.async(["/bin/cp", "-rf", binaryPath, "/usr/local/bin/tuist"])
            try system.async(["/bin/rm", binaryPath])
        }
    }
}
