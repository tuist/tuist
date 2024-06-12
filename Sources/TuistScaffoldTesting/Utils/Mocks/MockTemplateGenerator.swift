import Foundation
import Path
import TuistCore

@testable import TuistScaffold

public final class MockTemplateGenerator: TemplateGenerating {
    public var generateStub: ((Template, AbsolutePath, [String: TuistCore.Template.Attribute.Value]) throws -> Void)?

    public func generate(
        template: Template,
        to destinationPath: AbsolutePath,
        attributes: [String: TuistCore.Template.Attribute.Value]
    ) throws {
        try generateStub?(template, destinationPath, attributes)
    }
}
