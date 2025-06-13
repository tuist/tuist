import Path
import XcodeGraph
@testable import TuistGenerator

final class MockSynthesizedResourceInterfaceGenerator: SynthesizedResourceInterfacesGenerating {
    var renderStub: ((
        ResourceSynthesizer.Parser,
        [String: ResourceSynthesizer.Parser.Option],
        String,
        [String: ResourceSynthesizer.Template.Parameter],
        String,
        String?,
        [AbsolutePath]
    ) throws -> String)?
    func render(
        parser: ResourceSynthesizer.Parser,
        parserOptions: [String: ResourceSynthesizer.Parser.Option],
        templateString: String,
        templateParameters: [String: ResourceSynthesizer.Template.Parameter],
        name: String,
        bundleName: String?,
        paths: [AbsolutePath]
    ) throws -> String {
        try renderStub?(parser, parserOptions, templateString, templateParameters, name, bundleName, paths) ?? ""
    }
}
