import Foundation
import TSCBasic
import TuistGraph
@testable import TuistKit

class MockProjectEditor: ProjectEditing {
    func edit(at editingPath: TSCBasic.AbsolutePath,
              in destinationDirectory: TSCBasic.AbsolutePath,
              onlyCurrentDirectory: Bool,
              plugins: TuistGraph.Plugins) throws -> TSCBasic.AbsolutePath {
            return editingPath
    }
}
