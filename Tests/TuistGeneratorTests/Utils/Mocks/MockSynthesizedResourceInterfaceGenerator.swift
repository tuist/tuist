import TSCBasic
import TuistGraph
@testable import TuistGenerator

final class MockSynthesizedResourceInterfaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((
        ResourceSynthesizer.Parser,
        [String: ResourceSynthesizer.Parser.Option],
        String,
        String,
        String?,
        [AbsolutePath]
    ) throws -> String)?
    func render(
        parser: ResourceSynthesizer.Parser,
        parserOptions: [String: ResourceSynthesizer.Parser.Option],
        templateString: String,
        name: String,
        bundleName: String?,
        paths: [AbsolutePath]
    ) throws -> String {
        try renderStub?(parser, parserOptions, templateString, name, bundleName, paths) ?? ""
    }
}
