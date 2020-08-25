import TSCBasic
@testable import TuistGenerator

final class MockNamespaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((SynthesizedResourceInterfaceType, String, [AbsolutePath]) throws -> String)?
    func render(
        _ namespaceType: SynthesizedResourceInterfaceType,
        name: String,
        paths: [AbsolutePath]
    ) throws -> String {
        try renderStub?(namespaceType, name, paths) ?? ""
    }
}
