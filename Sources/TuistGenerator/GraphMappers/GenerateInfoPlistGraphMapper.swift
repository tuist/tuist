import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj

/// A mapper that generates derived Info.plist files for targets hose Info.plist
/// file is defined as part of the manifest
public class GenerateInfoPlistGraphMapper: GraphMapping {
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

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let targetNodeMapper = TargetNodeGraphMapper(transform: {
            try self.map(targetNode: $0, graph: graph)
        })
        return try targetNodeMapper.map(graph: graph)
    }

    // MARK: - Fileprivate

    fileprivate func map(targetNode: TargetNode, graph: Graph) throws -> (TargetNode, [SideEffectDescriptor]) {
        // There's nothing to do
        guard let infoPlist = targetNode.target.infoPlist else {
            return (targetNode, [])
        }

        // Get the Info.plist that needs to be generated
        guard let dictionary = infoPlistDictionary(infoPlist: infoPlist,
                                                   project: targetNode.project,
                                                   target: targetNode.target,
                                                   graph: graph) else {
            return (targetNode, [])
        }
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary,
                                                      format: .xml,
                                                      options: 0)

        let infoPlistPath = targetNode.project.path
            .appending(component: Constants.DerivedFolder.name)
            .appending(component: Constants.DerivedFolder.infoPlists)
            .appending(component: "\(targetNode.target.name).plist")
        let sideEffect = SideEffectDescriptor.file(FileDescriptor(path: infoPlistPath, contents: data))

        let newTarget = targetNode.target.with(infoPlist: InfoPlist.file(path: infoPlistPath))
        let newTargetNode = TargetNode(project: targetNode.project.replacing(target: targetNode.target, with: newTarget),
                                       target: newTarget,
                                       dependencies: targetNode.dependencies)
        return (newTargetNode, [sideEffect])
    }

    fileprivate func infoPlistDictionary(infoPlist: InfoPlist,
                                         project: Project,
                                         target: Target,
                                         graph: Graph) -> [String: Any]? {
        switch infoPlist {
        case let .dictionary(content):
            return content.mapValues { $0.value }
        case let .extendingDefault(extended):
            if let content = infoPlistContentProvider.content(graph: graph,
                                                              project: project,
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
