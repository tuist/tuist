import TSCBasic
import TuistGraph
@testable import TuistGenerator

final class MockSynthesizedResourceInterfaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((ResourceSynthesizer.Parser, String, String, [AbsolutePath]) throws -> String)?
    func render(
        parser: ResourceSynthesizer.Parser,
        templateString: String,
        name: String,
        paths: [AbsolutePath]
    ) throws -> String {
        try renderStub?(parser, templateString, name, paths) ?? ""
    }
}
