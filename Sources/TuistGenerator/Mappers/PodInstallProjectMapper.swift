import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// A mapper that returns the side effects for installing Pods in a given project..
public class PodInstallProjectMapper: ProjectMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        var podProjectPaths = project.podProjectPaths

        let podProjectPathsToAdd = project.targets
            .flatMap(\.dependencies)
            .compactMap { (dependency) -> AbsolutePath? in
                guard case let Dependency.cocoapods(path) = dependency else { return nil }
                return path
            }
            .map { $0.appending(RelativePath("Pods/Pods.xcodeproj")) }
        podProjectPaths.formUnion(podProjectPathsToAdd)
        project.podProjectPaths = podProjectPaths

        // Side effects
        let sideEffects = podProjectPaths.map { SideEffectDescriptor.installPods($0.parentDirectory.parentDirectory) }

        return (project, sideEffects)
    }
}
