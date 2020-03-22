import Basic
import Foundation
import TuistCore

@testable import TuistGenerator
@testable import TuistSupportTesting

final class MockEmbedScriptGenerator: EmbedScriptGenerating {
    var scriptArgs: [(AbsolutePath, [GraphDependencyReference])] = []
    var scriptStub: Result<EmbedScript, Error>?

    func script(sourceRootPath: AbsolutePath,
                frameworkReferences: [GraphDependencyReference]) throws -> EmbedScript {
        scriptArgs.append((sourceRootPath, frameworkReferences))
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
