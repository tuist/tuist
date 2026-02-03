import Foundation
import Mockable
import Path
import TuistCore
import XcodeGraph

@Mockable
public protocol Generating {
    @discardableResult
    func load(path: AbsolutePath, options: TuistGeneratedProjectOptions.GenerationOptions?) async throws -> Graph
    func generate(path: AbsolutePath, options: TuistGeneratedProjectOptions.GenerationOptions?) async throws -> AbsolutePath
    func generateWithGraph(path: AbsolutePath, options: TuistGeneratedProjectOptions.GenerationOptions?) async throws
        -> (AbsolutePath, Graph, MapperEnvironment)
}
