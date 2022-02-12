import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
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

        let infoPlistPath = project.path
            .appending(component: derivedDirectoryName)
            .appending(component: infoPlistsDirectoryName)
            .appending(component: "\(target.name).plist")
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
