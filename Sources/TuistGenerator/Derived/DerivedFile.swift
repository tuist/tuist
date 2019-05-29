import Basic
import Foundation

enum DerivedFile {
    /// It represents a generated Info.plist file.
    case infoPlist(target: String)

    /// Returns the absolute path to the derived file that Tuist generates.
    ///
    /// - Parameter sourceRootPath: Directory where the Xcode project gets genreated.
    /// - Returns: The absolute path to the derived file.
    func path(sourceRootPath: AbsolutePath) -> AbsolutePath {
        switch self {
        case let .infoPlist(targetName):
            return DerivedFile
                .infoPlistsPath(sourceRootPath: sourceRootPath)
                .appending(component: "\(targetName).plist")
        }
    }

    /// Returns the path to the directory where all generated Info.plist files will be.
    ///
    /// - Parameter sourceRootPath: Directory where the Xcode project gets genreated.
    /// - Returns: The path to the directory where all the Info.plist files will be generated.
    static func infoPlistsPath(sourceRootPath: AbsolutePath) -> AbsolutePath {
        return sourceRootPath
            .appending(component: "Derived")
            .appending(component: "InfoPlists")
    }
}
