import TSCBasic
@testable import TuistGenerator

final class MockNamespaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((SynthesizedResourceInterfaceType, [AbsolutePath]) throws -> [(name: String, contents: String)])?
    func render(_ namespaceType: SynthesizedResourceInterfaceType, paths: [AbsolutePath]) throws -> [(name: String, contents: String)] {
        try renderStub?(namespaceType, paths) ?? []
    }
}
