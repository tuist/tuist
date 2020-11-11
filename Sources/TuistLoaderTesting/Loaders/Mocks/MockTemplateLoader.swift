import Foundation
import TSCBasic
import TuistCore
import TuistLoader

public final class MockTemplateLoader: TemplateLoading {
    public var loadTemplateStub: ((AbsolutePath, Plugins) throws -> Template)?
    public func loadTemplate(at path: AbsolutePath, plugins: Plugins) throws -> Template {
        try loadTemplateStub?(path, plugins) ?? Template(description: "", attributes: [], files: [])
    }
}
