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
        // Download
        let installScriptPath: AbsolutePath!
        #if DEBUG
            installScriptPath = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .removingLastComponent()
                .appending(RelativePath("script/install"))
        #else
            installScriptPath = AbsolutePath(Bundle(for: EnvUpdater.self).bundleURL.path)
                .appending(RelativePath("script/install"))
        #endif
        try System.shared.runAndPrint([installScriptPath.pathString])
    }
}
