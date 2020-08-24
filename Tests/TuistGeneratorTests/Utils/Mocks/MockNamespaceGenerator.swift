import TSCBasic
@testable import TuistGenerator

final class MockNamespaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((SynthesizedResourceInterfaceType, String, [AbsolutePath]) throws -> [(name: String, contents: String)])?
    func render(
        _ namespaceType: SynthesizedResourceInterfaceType,
        name: String,
        paths: [AbsolutePath]
    ) throws -> [(name: String, contents: String)] {
        try renderStub?(namespaceType, name, paths) ?? []
    }
}
