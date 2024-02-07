import Foundation
import TSCBasic
import TuistGraph

@testable import TuistCore
@testable import TuistScaffold

public final class MockTemplateGenerator: TemplateGenerating {
    public var generateStub: ((Template, AbsolutePath, [String: TuistGraph.Template.Attribute.Value]) throws -> Void)?

    public func generate(
        template: Template,
        to destinationPath: AbsolutePath,
        attributes: [String: TuistGraph.Template.Attribute.Value]
    ) throws {
        try generateStub?(template, destinationPath, attributes)
    }
}
