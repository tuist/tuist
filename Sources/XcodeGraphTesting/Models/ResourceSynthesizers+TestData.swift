import Foundation
@testable import XcodeGraph

extension XcodeGraph.ResourceSynthesizer {
    public static func test(
        parser: Parser = .assets,
        parserOptions: [String: Parser.Option] = [:],
        extensions: Set<String> = ["xcassets"],
        template: Template = .defaultTemplate("Assets")
    ) -> Self {
        ResourceSynthesizer(parser: parser, parserOptions: parserOptions, extensions: extensions, template: template)
    }
}
