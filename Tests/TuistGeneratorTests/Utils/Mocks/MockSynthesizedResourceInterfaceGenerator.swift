import TSCBasic
@testable import TuistGenerator

final class MockSynthesizedResourceInterfaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((SynthesizedResourceInterfaceType, String, String, [AbsolutePath]) throws -> String)?
    func render(
        _ namespaceType: SynthesizedResourceInterfaceType,
        templateString: String,
        name: String,
        paths: [AbsolutePath]
    ) throws -> String {
        try renderStub?(namespaceType, templateString, name, paths) ?? ""
    }
}
