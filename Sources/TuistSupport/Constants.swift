import Foundation

public enum Constants {
    public static let versionFileName = ".tuist-version"
    public static let binFolderName = ".tuist-bin"
    public static let binName = "tuist"
    public static let gitRepositoryURL = "https://github.com/tuist/tuist.git"
    public static let communityURL = "https://community.tuist.io"
    public static let version = "1.41.0"
    public static let bundleName: String = "tuist.zip"
    public static let trueValues: [String] = ["1", "true", "TRUE", "yes", "YES"]
    public static let tuistDirectoryName: String = "Tuist"

    public static let helpersDirectoryName: String = "ProjectDescriptionHelpers"
    public static let signingDirectoryName: String = "Signing"

    public static let masterKey = "master.key"
    public static let encryptedExtension = "encrypted"
    public static let templatesDirectoryName: String = "Templates"
    public static let resourceSynthesizersDirectoryName: String = "ResourceSynthesizers"
    public static let vendorDirectoryName: String = "vendor"
    public static let twitterHandle: String = "tuistio"
    public static let joinSlackURL: String = "https://slack.tuist.io/"
    public static let tuistGeneratedFileName = ".tuist-generated"

    public enum Vendor {
        public static let swiftLint = "swiftlint"
        public static let swiftDoc = "swift-doc"
        public static let xcbeautify = "xcbeautify"
    }

    public enum DependenciesDirectory {
        public static let name = "Dependencies"
        public static let lockfilesDirectoryName = "Lockfiles"
        public static let cartfileResolvedName = "Cartfile.resolved"
        public static let packageResolvedName = "Package.resolved"
        public static let carthageDirectoryName = "Carthage"
        public static let swiftPackageManagerDirectoryName = "SwiftPackageManager"
    }

    public enum DerivedDirectory {
        public static let name = "Derived"
        public static let infoPlists = "InfoPlists"
        public static let sources = "Sources"
        public static let signingKeychain = "signing.keychain"
    }

    public enum AsyncQueue {
        public static let directoryName: String = "Queue"
    }

    /// Pass these variables to make custom configuration of tuist
    /// These variables are not supposed to be used by end users
    /// But only eg. for acceptance tests and other cases needed internally
    public enum EnvironmentVariables {
        public static let verbose = "TUIST_VERBOSE"
        public static let colouredOutput = "TUIST_COLOURED_OUTPUT"
        public static let versionsDirectory = "TUIST_VERSIONS_DIRECTORY"
        @available(*, deprecated, message: "This is used only for acceptance tests, see https://github.com/tuist/tuist/issues/2777")
        public static let forceConfigCacheDirectory = "TUIST_FORCE_CONFIG_CACHE_DIRECTORY"
        public static let automationPath = "TUIST_AUTOMATION_PATH"
        public static let queueDirectory = "TUIST_QUEUE_DIRECTORY"
        public static let cloudToken = "TUIST_CLOUD_TOKEN"
        public static let cacheManifests = "TUIST_CACHE_MANIFESTS"
        public static let statsOptOut = "TUIST_STATS_OPT_OUT"
    }

    public enum GoogleCloud {
        public static let relasesBucketURL = "https://storage.googleapis.com/tuist-releases/"
    }
}
