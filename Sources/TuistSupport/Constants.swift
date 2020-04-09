import Foundation

public struct Constants {
    public static let versionFileName = ".tuist-version"
    public static let binFolderName = ".tuist-bin"
    public static let binName = "tuist"
    public static let gitRepositoryURL = "https://github.com/tuist/tuist.git"
    public static let version = "1.6.0"
    public static let swiftVersion: String = "5.2"
    public static let bundleName: String = "tuist.zip"
    public static let trueValues: [String] = ["1", "true", "TRUE", "yes", "YES"]
    public static let tuistDirectoryName: String = "Tuist"
    public static let helpersDirectoryName: String = "ProjectDescriptionHelpers"
    public static let signingDirectoryName: String = "Signing"
    public static let masterKey = "master.key"
    public static let templatesDirectoryName: String = "Templates"
    public static let twitterHandle: String = "tuistio"
    public static let joinSlackURL: String = "https://slack.tuist.io/"

    public struct DerivedFolder {
        public static let name = "Derived"
    }

    public struct EnvironmentVariables {
        public static let colouredOutput = "TUIST_COLOURED_OUTPUT"
        public static let versionsDirectory = "TUIST_VERSIONS_DIRECTORY"
        public static let cacheDirectory = "TUIST_CACHE_DIRECTORY"
        public static let cloudToken = "TUIST_CLOUD_TOKEN"
    }

    public struct GoogleCloud {
        public static let relasesBucketURL = "https://storage.googleapis.com/tuist-releases/"
    }
}
