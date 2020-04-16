import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj

/// A mapper that generates derived Info.plist files for targets hose Info.plist
/// file is defined as part of the manifest
public class GenerateInfoPlistProjectMapper: ProjectMapping {
    // MARK: - Attributes

    let infoPlistContentProvider: InfoPlistContentProviding

    /// Default initializer.
    public convenience init() {
        self.init(infoPlistContentProvider: InfoPlistContentProvider())
    }

    /// Initializes the mapper with its attributes.
    ///
    /// - Parameters:
    ///   - infoPlistContentProvider: Info.plist content provider.
    init(infoPlistContentProvider: InfoPlistContentProviding) {
        self.infoPlistContentProvider = infoPlistContentProvider
    }

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var results = (targets: [Target](), sideEffects: [SideEffectDescriptor]())
        results = try project.targets.reduce(into: results) { results, target in
            let (updatedTarget, sideEffects) = try map(target: target, project: project)
            results.targets.append(updatedTarget)
            results.sideEffects.append(contentsOf: sideEffects)
        }

        return (project.with(targets: results.targets), results.sideEffects)
    }

    // MARK: - Fileprivate

    fileprivate func map(target: Target, project: Project) throws -> (Target, [SideEffectDescriptor]) {
        // There's nothing to do
        guard let infoPlist = target.infoPlist else {
            return (target, [])
        }

        // Get the Info.plist that needs to be generated
        guard let dictionary = infoPlistDictionary(infoPlist: infoPlist,
                                                   project: project,
                                                   target: target) else {
            return (target, [])
        }
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary,
                                                      format: .xml,
                                                      options: 0)

        let infoPlistPath = project.path
            .appending(component: Constants.DerivedFolder.name)
            .appending(component: Constants.DerivedFolder.infoPlists)
            .appending(component: "\(target.name).plist")
        let sideEffect = SideEffectDescriptor.file(FileDescriptor(path: infoPlistPath, contents: data))

        let newTarget = target.with(infoPlist: InfoPlist.generatedFile(path: infoPlistPath))

        return (newTarget, [sideEffect])
    }

    fileprivate func infoPlistDictionary(infoPlist: InfoPlist,
                                         project: Project,
                                         target: Target) -> [String: Any]? {
        switch infoPlist {
        case let .dictionary(content):
            return content.mapValues { $0.value }
        case let .extendingDefault(extended):
            if let content = infoPlistContentProvider.content(project: project,
                                                              target: target,
                                                              extendedWith: extended) {
                return content
            }
            return nil
        default:
            return nil
        }
    }
}

extension Array where Element: Equatable {
    func replacing(_ oldElement: Element, with newElement: Element) -> [Element] {
        map {
            $0 == oldElement ? newElement : $0
        }
    }
}
