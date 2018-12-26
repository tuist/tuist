import Basic
import Foundation
import xcodeproj

class GeneratedProject {
    /// Path to the project .xcodeproj directory
    let path: AbsolutePath

    /// Dictionary whose keys are the target names and the value the Xcode targets.
    let targets: [String: PBXNativeTarget]

    /// Initializes the GeneratedProject with its attributes.
    ///
    /// - Parameters:
    ///   - path: Dictionary whose keys are the target names and the value the Xcode targets.
    ///   - targets: Dictionary whose keys are the target names and the value the Xcode targets.
    init(path: AbsolutePath,
         targets: [String: PBXNativeTarget]) {
        self.path = path
        self.targets = targets
    }
}
