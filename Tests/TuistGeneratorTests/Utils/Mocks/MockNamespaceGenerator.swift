import TSCBasic
@testable import TuistGenerator

final class MockNamespaceGenerator: NamespaceGenerating {
    var renderStub: ((NamespaceType, [AbsolutePath]) throws -> [(name: String, contents: String)])?
    func render(_ namespaceType: NamespaceType, paths: [AbsolutePath]) throws -> [(name: String, contents: String)] {
        try renderStub?(namespaceType, paths) ?? []
    }

    var generateNamespaceScriptStub: (() -> String)?
    func generateNamespaceScript() -> String {
        generateNamespaceScriptStub?() ?? ""
    }
}
