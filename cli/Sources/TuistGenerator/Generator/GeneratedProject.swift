import Foundation
import Path
import PathKit
import XcodeProj

struct GeneratedProject {
    /// A reference to the .xcodeproj which was generated.
    let pbxproj: PBXProj

    /// Path to the project .xcodeproj directory
    let path: AbsolutePath

    /// Dictionary whose keys are the target names and the value the Xcode targets.
    let targets: [String: PBXTarget]

    /// Project name with the .xcodeproj extension.
    let name: String

    /// Returns a GeneratedProject with the given path.
    ///
    /// - Parameter path: Path to the project (.xcodeproj)
    /// - Returns: GeneratedProject instance.
    func at(path: AbsolutePath) -> GeneratedProject {
        GeneratedProject(
            pbxproj: pbxproj,
            path: path,
            targets: targets,
            name: name
        )
    }
}
