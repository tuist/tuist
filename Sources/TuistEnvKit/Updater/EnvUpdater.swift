import Basic
import Foundation
import SPMUtility
import TuistSupport

/// Protocol that defines the interface to update the environment.
protocol EnvUpdating {
    /// Updates the local tuistenv installation.
    ///
    /// - Throws: An error if the installation fails.
    func update() throws
}

final class EnvUpdater: EnvUpdating {
    /// GitHub API client.
    let githubClient: GitHubClienting

    /// Initializes the env update with its attributes.
    ///
    /// - Parameters:
    ///   - system: System instance to run commands.
    ///   - githubClient: GitHub API client.
    init(githubClient: GitHubClienting = GitHubClient()) {
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

        try FileHandler.shared.inTemporaryDirectory { directory in
            // Download
            let fileName = asset.downloadURL.lastPathComponent
            let downloadPath = directory.appending(component: fileName)
            try System.shared.run("/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, asset.downloadURL.absoluteString)
            try System.shared.run("/usr/bin/unzip", "-o", downloadPath.pathString, "-d", "/tmp/")
            let binaryPath = "/tmp/tuistenv"
            try System.shared.run(["/bin/chmod", "+x", binaryPath])

            // Replace
            try System.shared.async(["/bin/cp", "-rf", binaryPath, "/usr/local/bin/tuist"])
            try System.shared.async(["/bin/rm", binaryPath])
        }
    }
}
