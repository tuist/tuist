import Basic
import Foundation
import TuistTemplate

public final class MockTemplateGenerator: TemplateGenerating {
    public var generateStub: ((AbsolutePath, AbsolutePath, [String]) throws -> Void)?

    public func generate(at path: AbsolutePath,
                         to _: AbsolutePath,
                         attributes: [String]) throws {
        try generateStub?(path, path, attributes)
    }
}
