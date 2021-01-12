import Foundation
import TSCBasic
import TuistSupport

/// Protocol that defines the interface to update the environment.
protocol EnvUpdating {
    /// Updates the local tuistenv installation.
    ///
    /// - Throws: An error if the installation fails.
    func update() throws
}

final class EnvUpdater: EnvUpdating {
    /// Google Cloud Storage instance.
    let googleCloudStorageClient: GoogleCloudStorageClienting

    /// Initializes the env update with its attributes.
    ///
    /// - Parameters:
    ///   - googleCloudStorageClient: Google Cloud Storage instance.
    init(googleCloudStorageClient: GoogleCloudStorageClienting = GoogleCloudStorageClient()) {
        self.googleCloudStorageClient = googleCloudStorageClient
    }

    /// Updates the local tuistenv installation.
    ///
    /// - Throws: An error if the installation fails.
    func update() throws {
        try FileHandler.shared.inTemporaryDirectory { directory in
            // Download
            let outputPath = googleCloudStorageClient.latestTuistEnvBundleURL().absoluteString
            let downloadPath = directory.appending(component: "tuistenv.zip")
            try System.shared.run("/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, outputPath)
            try System.shared.run("/usr/bin/unzip", "-o", downloadPath.pathString, "-d", "/tmp/")
            let binaryPath = "/tmp/tuistenv"
            try System.shared.run(["/bin/chmod", "+x", binaryPath])

            // Replace
            try System.shared.async(["/bin/cp", "-rf", binaryPath, "/usr/local/bin/tuist"])
            try System.shared.async(["/bin/ln", "-sf", "/usr/local/bin/tuist", "/usr/local/bin/swift-project"])
            try System.shared.async(["/bin/rm", binaryPath])
        }
    }
}
