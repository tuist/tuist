import Foundation
import TuistCore
import TuistSupport

/// A mapper that returns side effects to delete the derived directory of each project of the graph.
public class DeleteDerivedDirectoryGraphMapper: GraphMapping {
    public init() {}

    // MARK: - GraphMapping

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        logger.debug("Determining the /Derived directories that should be delted")
        var sideEffects = [SideEffectDescriptor]()

        graph.projects.forEach { project in
            let derivedDirectoryPath = project.path.appending(component: Constants.DerivedFolder.name)
            let directoryDescriptor = DirectoryDescriptor(path: derivedDirectoryPath, state: .absent)
            sideEffects.append(.directory(directoryDescriptor))
        }

        return (graph, sideEffects)
    }
}
