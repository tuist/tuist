import Foundation

public struct Constants {
    public static let versionFileName = ".tuist-version"
    public static let binFolderName = ".tuist-bin"
    public static let binName = "tuist"
    public static let gitRepositoryURL = "https://github.com/tuist/tuist.git"
    public static let version = "1.11.0"
    public static let bundleName: String = "tuist.zip"
    public static let trueValues: [String] = ["1", "true", "TRUE", "yes", "YES"]
    public static let tuistDirectoryName: String = "Tuist"
    public static let derivedFolderName = "Derived"
    public static let helpersDirectoryName: String = "ProjectDescriptionHelpers"
    public static let signingDirectoryName: String = "Signing"
    public static let signingKeychain = "signing.keychain"
    public static let masterKey = "master.key"
    public static let encryptedExtension = "encrypted"
    public static let templatesDirectoryName: String = "Templates"
    public static let twitterHandle: String = "tuistio"
    public static let joinSlackURL: String = "https://slack.tuist.io/"
    public static let tuistGeneratedFileName = ".tuist-generated"

    public struct EnvironmentVariables {
        public static let colouredOutput = "TUIST_COLOURED_OUTPUT"
        public static let versionsDirectory = "TUIST_VERSIONS_DIRECTORY"
        public static let cacheDirectory = "TUIST_CACHE_DIRECTORY"
        public static let cloudToken = "TUIST_CLOUD_TOKEN"
        public static let cacheManifests = "TUIST_CACHE_MANIFESTS"
    }

    public struct GoogleCloud {
        public static let relasesBucketURL = "https://storage.googleapis.com/tuist-releases/"
    }
}
