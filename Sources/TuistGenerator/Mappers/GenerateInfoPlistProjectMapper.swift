import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj

/// A project mapper that generates derived Info.plist files for targets that define it as a dictonary.
public final class GenerateInfoPlistProjectMapper: ProjectMapping {
    private let infoPlistContentProvider: InfoPlistContentProviding
    private let derivedDirectoryName: String
    private let infoPlistsDirectoryName: String

    public convenience init(
        derivedDirectoryName: String = Constants.DerivedDirectory.name,
        infoPlistsDirectoryName: String = Constants.DerivedDirectory.infoPlists
    ) {
        self.init(
            infoPlistContentProvider: InfoPlistContentProvider(),
            derivedDirectoryName: derivedDirectoryName,
            infoPlistsDirectoryName: infoPlistsDirectoryName
        )
    }

    init(
        infoPlistContentProvider: InfoPlistContentProviding,
        derivedDirectoryName: String,
        infoPlistsDirectoryName: String
    ) {
        self.infoPlistContentProvider = infoPlistContentProvider
        self.derivedDirectoryName = derivedDirectoryName
        self.infoPlistsDirectoryName = infoPlistsDirectoryName
    }

    // MARK: - ProjectMapping

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        logger.debug("Transforming project \(project.name): Synthesizing Info.plist")

        let results = try project.targets.values
            .reduce(into: (targets: [String: Target](), sideEffects: [SideEffectDescriptor]())) { results, target in
                let (updatedTarget, sideEffects) = try map(target: target, project: project)
                results.targets[updatedTarget.name] = updatedTarget
                results.sideEffects.append(contentsOf: sideEffects)
            }
        var project = project
        project.targets = results.targets

        return (project, results.sideEffects)
    }

    // MARK: - Private

    private func map(target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        // There's nothing to do
        guard let infoPlist = target.infoPlist else {
            return (target, [])
        }

        // Get the Info.plist that needs to be generated
        guard let dictionary = infoPlistDictionary(
            infoPlist: infoPlist,
            project: project,
            target: target
        )
        else {
            return (target, [])
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )

        let infoPlistPath = project.derivedDirectoryPath(for: target)
            .appending(component: infoPlistsDirectoryName)
            .appending(component: "\(target.name)-Info.plist")
        let sideEffect = SideEffectDescriptor.file(FileDescriptor(path: infoPlistPath, contents: data))

        let newTarget = target.with(infoPlist: InfoPlist.generatedFile(path: infoPlistPath, data: data))

        return (newTarget, [sideEffect])
    }

    private func infoPlistDictionary(
        infoPlist: InfoPlist,
        project: Project,
        target: Target
    ) -> [String: Any]? {
        switch infoPlist {
        case let .dictionary(content):
            return content.mapValues { $0.value }
        case let .extendingDefault(extended):
            if let content = infoPlistContentProvider.content(
                project: project,
                target: target,
                extendedWith: extended
            ) {
                return content
            }
            return nil
        default:
            return nil
        }
    }
}
