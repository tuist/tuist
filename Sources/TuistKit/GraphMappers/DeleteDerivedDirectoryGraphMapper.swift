import Foundation
import TuistCore
import TuistSupport

/// A mapper that returns side effects to delete the derived directory of each project of the graph.
class DeleteDerivedDirectoryGraphMapper: GraphMapping {
    func map(graph: Graph) throws -> (Graph, Set<SideEffectDescriptor>) {
        var sideEffects = Set<SideEffectDescriptor>()

        graph.projects.forEach { project in
            let derivedDirectoryPath = project.path.appending(component: Constants.DerivedFolder.name)
            let directoryDescriptor = DirectoryDescriptor(path: derivedDirectoryPath, state: .absent)
            sideEffects.insert(.directory(directoryDescriptor))
        }

        return (graph, sideEffects)
    }
}
