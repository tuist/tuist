import Foundation
import PathKit
import TSCBasic
import XcodeProj

final class GeneratedProject {
    /// A reference to the .xcodeproj which was generated.
    let pbxproj: PBXProj

    /// Path to the project .xcodeproj directory
    let path: AbsolutePath

    /// Dictionary whose keys are the target names and the value the Xcode targets.
    let targets: [String: PBXNativeTarget]

    /// Dictionary whose keys are the aggregate target names and the value the Xcode targets.
    let aggregateTargets: [String: PBXAggregateTarget]

    /// Project name with the .xcodeproj extension.
    let name: String

    /// Initializes the GeneratedProject with its attributes.
    ///
    /// - Parameters:
    ///   - pbxproj: Xcode project
    ///   - path: Dictionary whose keys are the target names and the value the Xcode targets.
    ///   - targets: Dictionary whose keys are the target names and the value the Xcode targets.
    ///   - aggregateTargets: Dictionary whose keys are the aggregate target names and the value the Xcode targets.
    ///   - name: Project name with .xcodeproj extension
    init(
        pbxproj: PBXProj,
        path: AbsolutePath,
        targets: [String: PBXNativeTarget],
        aggregateTargets: [String: PBXAggregateTarget],
        name: String
    ) {
        self.pbxproj = pbxproj
        self.path = path
        self.targets = targets
        self.aggregateTargets = aggregateTargets
        self.name = name
    }

    /// Returns a GeneratedProject with the given path.
    ///
    /// - Parameter path: Path to the project (.xcodeproj)
    /// - Returns: GeneratedProject instance.
    func at(path: AbsolutePath) -> GeneratedProject {
        GeneratedProject(
            pbxproj: pbxproj,
            path: path,
            targets: targets,
            aggregateTargets: aggregateTargets,
            name: name
        )
    }
}
