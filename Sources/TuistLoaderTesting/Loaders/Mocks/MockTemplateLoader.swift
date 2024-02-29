import Foundation
import TSCBasic
import TuistGraph
import TuistLoader

public final class MockTemplateLoader: TemplateLoading {
    public var loadTemplateStub: ((AbsolutePath) throws -> Template)?
    public func loadTemplate(at path: AbsolutePath, plugins _: Plugins) throws -> Template {
        try loadTemplateStub?(path) ?? Template(description: "", attributes: [], items: [])
    }
}
