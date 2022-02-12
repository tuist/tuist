import Foundation
import TSCBasic
import TuistCore

@testable import TuistGenerator
@testable import TuistSupportTesting

final class MockEmbedScriptGenerator: EmbedScriptGenerating {
    var scriptArgs: [(AbsolutePath, [GraphDependencyReference], Bool)] = []
    var scriptStub: Result<EmbedScript, Error>?

    func script(
        sourceRootPath: AbsolutePath,
        frameworkReferences: [GraphDependencyReference],
        includeSymbolsInFileLists: Bool
    ) throws -> EmbedScript {
        scriptArgs.append((sourceRootPath, frameworkReferences, includeSymbolsInFileLists))
        if let scriptStub = scriptStub {
            switch scriptStub {
            case let .failure(error): throw error
            case let .success(script): return script
            }
        } else {
            throw TestError("call to embed script generator not mocked")
        }
    }
}
