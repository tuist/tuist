import Foundation
import TSCBasic
import XcodeProjectGenerator

@testable import TuistCore
@testable import TuistScaffold

public final class MockTemplateGenerator: TemplateGenerating {
    public var generateStub: ((Template, AbsolutePath, [String: XcodeProjectGenerator.Template.Attribute.Value]) throws -> Void)?

    public func generate(
        template: Template,
        to destinationPath: AbsolutePath,
        attributes: [String: XcodeProjectGenerator.Template.Attribute.Value]
    ) throws {
        try generateStub?(template, destinationPath, attributes)
    }
}
