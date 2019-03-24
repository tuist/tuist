import Basic
import Foundation
import PathKit
import xcodeproj

final class GeneratedProject {
    /// A reference to the .xcodeproj which was generated.
    let pbxproj: PBXProj

    /// Path to the project .xcodeproj directory
    let path: AbsolutePath

    /// Dictionary whose keys are the target names and the value the Xcode targets.
    let targets: [String: PBXNativeTarget]

    /// Project name with the .xcodeproj extension.
    let name: String

    /// Initializes the GeneratedProject with its attributes.
    ///
    /// - Parameters:
    ///   - path: Dictionary whose keys are the target names and the value the Xcode targets.
    ///   - targets: Dictionary whose keys are the target names and the value the Xcode targets.
    ///   - name: Project name with .xcodeproj extension
    init(pbxproj: PBXProj,
         path: AbsolutePath,
         targets: [String: PBXNativeTarget],
         name: String) {
        self.pbxproj = pbxproj
        self.path = path
        self.targets = targets
        self.name = name
    }

    /// Returns a GeneratedProject with the given path.
    ///
    /// - Parameter path: Path to the project (.xcodeproj)
    /// - Returns: GeneratedProject instance.
    func at(path: AbsolutePath) throws -> GeneratedProject {
        let xcode = try XcodeProj(pathString: path.asString)

        return GeneratedProject(pbxproj: xcode.pbxproj,
                                path: path,
                                targets: targets,
                                name: name)
    }
}
