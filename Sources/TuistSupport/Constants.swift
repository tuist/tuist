import Foundation

public enum Constants {
    public static let versionFileName = ".tuist-version"
    public static let binFolderName = ".tuist-bin"
    public static let binName = "tuist"
    public static let gitRepositoryURL = "https://github.com/tuist/tuist.git"
    public static let githubAPIURL = "https://api.github.com"
    public static let githubSlug = "tuist/tuist"
    public static let communityURL = "https://github.com/tuist/tuist/discussions/categories/general"
    public static let version = "4.3.4"
    public static let bundleName: String = "tuist.zip"
    public static let trueValues: [String] = ["1", "true", "TRUE", "yes", "YES"]
    public static let tuistDirectoryName: String = "Tuist"

    public static let helpersDirectoryName: String = "ProjectDescriptionHelpers"
    public static let signingDirectoryName: String = "Signing"

    public static let masterKey = "master.key"
    public static let encryptedExtension = "encrypted"
    public static let templatesDirectoryName: String = "Templates"
    public static let resourceSynthesizersDirectoryName: String = "ResourceSynthesizers"
    public static let stencilsDirectoryName: String = "Stencils"
    public static let vendorDirectoryName: String = "vendor"
    public static let twitterHandle: String = "tuistio"
    public static let joinSlackURL: String = "https://slack.tuist.io/"
    public static let tuistGeneratedFileName = ".tuist-generated"

    /// The cache version.
    /// This should change only when it changes the logic to map a `TuistGraph.Target` to a cached build artifact.
    /// Changing this results in changing the target hash and hence forcing a rebuild of its artifact.
    public static let cacheVersion = "1.0.0"

    public enum SwiftPackageManager {
        public static let packageSwiftName = "Package.swift"
        public static let packageResolvedName = "Package.resolved"
        public static let packageBuildDirectoryName = ".build"
    }

    public enum DerivedDirectory {
        public static let name = "Derived"
        public static let infoPlists = "InfoPlists"
        public static let entitlements = "Entitlements"
        public static let privacyManifest = "PrivacyManifests"
        public static let moduleMaps = "ModuleMaps"
        public static let sources = "Sources"
        public static let signingKeychain = "signing.keychain"
        public static let dependenciesDerivedDirectory = "tuist-derived"
    }

    public enum AsyncQueue {
        public static let directoryName: String = "Queue"
    }

    /// Pass these variables to make custom configuration of tuist
    /// These variables are not supposed to be used by end users
    /// But only eg. for acceptance tests and other cases needed internally
    public enum EnvironmentVariables {
        public static let verbose = "TUIST_CONFIG_VERBOSE"
        public static let versionsDirectory = "TUIST_CONFIG_VERSIONS_DIRECTORY"
        public static let automationPath = "TUIST_CONFIG_AUTOMATION_PATH"
        public static let queueDirectory = "TUIST_CONFIG_QUEUE_DIRECTORY"
        public static let cacheManifests = "TUIST_CONFIG_CACHE_MANIFESTS"
        public static let statsOptOut = "TUIST_CONFIG_STATS_OPT_OUT"
        public static let githubAPIToken = "TUIST_CONFIG_GITHUB_API_TOKEN"
        public static let detailedLog = "TUIST_CONFIG_DETAILED_LOG"
        public static let osLog = "TUIST_CONFIG_OS_LOG"
        /// `tuistBinaryPath` is used for specifying the exact tuist binary in tuist tasks.
        public static let tuistBinaryPath = "TUIST_CONFIG_BINARY_PATH"
    }
}
