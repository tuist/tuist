import Basic
import Foundation
import xcodeproj

final class GeneratedProject {
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
    init(path: AbsolutePath,
         targets: [String: PBXNativeTarget],
         name: String) {
        self.path = path
        self.targets = targets
        self.name = name
    }

    /// Returns a GeneratedProject with the given path.
    ///
    /// - Parameter path: Path to the project (.xcodeproj)
    /// - Returns: GeneratedProject instance.
    func at(path: AbsolutePath) -> GeneratedProject {
        return GeneratedProject(path: path,
                                targets: targets,
                                name: name)
    }
}
