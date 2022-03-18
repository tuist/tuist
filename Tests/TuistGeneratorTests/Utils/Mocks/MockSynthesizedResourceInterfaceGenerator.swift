import TSCBasic
import TuistGraph
@testable import TuistGenerator

final class MockSynthesizedResourceInterfaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((ResourceSynthesizer.Parser, String, String, String?, [AbsolutePath]) throws -> String)?
    func render(
        parser: ResourceSynthesizer.Parser,
        templateString: String,
        name: String,
        bundleName: String?,
        paths: [AbsolutePath]
    ) throws -> String {
        try renderStub?(parser, templateString, name, bundleName, paths) ?? ""
    }
}
