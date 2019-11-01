import Basic
import Foundation

@testable import TuistGenerator
@testable import TuistSupportTesting

final class MockEmbedScriptGenerator: EmbedScriptGenerating {
    var scriptArgs: [(AbsolutePath, [AbsolutePath])] = []
    var scriptStub: Result<EmbedScript, Error>?

    func script(sourceRootPath: AbsolutePath,
                frameworkPaths: [AbsolutePath]) throws -> EmbedScript {
        scriptArgs.append((sourceRootPath, frameworkPaths))
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
