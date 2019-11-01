import Foundation

public struct Constants {
    public static let versionFileName = ".tuist-version"
    public static let binFolderName = ".tuist-bin"
    public static let binName = "tuist"
    public static let gitRepositoryURL = "https://github.com/tuist/tuist.git"
    public static let version = "0.18.1"
    public static let swiftVersion: String = "5.0"
    public static let bundleName: String = "tuist.zip"
    public static let trueValues: [String] = ["1", "true", "TRUE", "yes", "YES"]
    public static let tuistFolderName: String = "Tuist"

    public struct EnvironmentVariables {
        public static let colouredOutput = "TUIST_COLOURED_OUTPUT"
    }

    public struct GoogleCloud {
        public static let relasesBucketURL = "https://storage.googleapis.com/tuist-releases/"
    }
}
