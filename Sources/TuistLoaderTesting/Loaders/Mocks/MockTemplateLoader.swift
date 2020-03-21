import Basic
import Foundation
import TuistCore
import TuistLoader

public final class MockTemplateLoader: TemplateLoading {
    public var loadTemplateStub: ((AbsolutePath) throws -> Template)?
    public func loadTemplate(at path: AbsolutePath) throws -> Template {
        try loadTemplateStub?(path) ?? Template(description: "", attributes: [], files: [])
    }
}
