import Foundation
import TSCBasic
import TuistGraph
@testable import TuistKit

class MockProjectEditor: ProjectEditing {
    var destinationDirectory: TSCBasic.AbsolutePath?
    var onlyCurrentDirectory: Bool = false
    var editingPath: TSCBasic.AbsolutePath?

    func edit(
        at editingPath: TSCBasic.AbsolutePath,
        in destinationDirectory: TSCBasic.AbsolutePath,
        onlyCurrentDirectory: Bool,
        plugins _: TuistGraph.Plugins
    ) throws -> TSCBasic.AbsolutePath {
        self.destinationDirectory = destinationDirectory
        self.onlyCurrentDirectory = onlyCurrentDirectory
        self.editingPath = editingPath

        return destinationDirectory
    }
}
