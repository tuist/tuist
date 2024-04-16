import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XcodeProj

/// A project mapper that generates derived privacyManifest files for targets that define it as a dictonary.
public final class GeneratePrivacyManifestProjectMapper: ProjectMapping {
    public init() {}

    // MARK: - ProjectMapping

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        logger.debug("Transforming project \(project.name): Synthesizing privacy manifest files'")

        let results = try project.targets
            .reduce(into: (targets: [Target](), sideEffects: [SideEffectDescriptor]())) { results, target in
                let (updatedTarget, sideEffects) = try map(target: target, project: project)
                results.targets.append(updatedTarget)
                results.sideEffects.append(contentsOf: sideEffects)
            }

        return (project.with(targets: results.targets), results.sideEffects)
    }

    // MARK: - Private

    private func map(target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        guard let privacyManifest = target.resources.privacyManifest else {
            return (target, [])
        }

        let dictionary: [String: Any] = [
            "NSPrivacyTracking": privacyManifest.tracking,
            "NSPrivacyTrackingDomains": privacyManifest.trackingDomains,
            "NSPrivacyCollectedDataTypes": privacyManifest.collectedDataTypes.map { $0.mapValues { $0.value } },
            "NSPrivacyAccessedAPITypes": privacyManifest.accessedApiTypes.map { $0.mapValues { $0.value } },
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )

        let privacyManifestPath = project.path
            .appending(component: Constants.DerivedDirectory.name)
            .appending(component: Constants.DerivedDirectory.privacyManifest)
            .appending(component: target.name)
            .appending(component: "PrivacyInfo.xcprivacy")
        let sideEffect = SideEffectDescriptor.file(FileDescriptor(path: privacyManifestPath, contents: data))

        var resources = target.resources
        resources.resources.append(.init(path: privacyManifestPath))

        var newTarget = target
        newTarget.resources = resources

        return (newTarget, [sideEffect])
    }
}
