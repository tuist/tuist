import Foundation
import Path
import XcodeGraph

@testable import TuistCore
@testable import TuistScaffold

public final class MockTemplateGenerator: TemplateGenerating {
    public var generateStub: ((Template, AbsolutePath, [String: XcodeGraph.Template.Attribute.Value]) throws -> Void)?

    public func generate(
        template: Template,
        to destinationPath: AbsolutePath,
        attributes: [String: XcodeGraph.Template.Attribute.Value]
    ) throws {
        try generateStub?(template, destinationPath, attributes)
    }
}
