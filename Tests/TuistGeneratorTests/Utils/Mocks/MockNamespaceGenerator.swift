import TSCBasic
@testable import TuistGenerator

final class MockNamespaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((SynthesizedResourceInterfaceType, String, AbsolutePath) throws -> (name: String, contents: String))?
    func render(
        _ namespaceType: SynthesizedResourceInterfaceType,
        name: String,
        path: AbsolutePath
    ) throws -> (name: String, contents: String) {
        try renderStub?(namespaceType, name, path) ?? (name: "", contents: "")
    }
}
