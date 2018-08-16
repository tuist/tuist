import Foundation

public class Constants {
    public static let versionFileName = ".tuist-version"
    public static let binFolderName = ".tuist-bin"
    public static let binName = "tuist"
    public static let gitRepositorySSH = "git@github.com:tuist/tuist.git"
    public static let version = "0.2.0"
    public static let swiftVersion: String = "4.1.2"

    public struct Manifest {
        public static let project = "Project.swift"
        public static let workspace = "Workspace.swift"
    }
}
