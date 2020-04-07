import Basic
import Foundation
import TuistCore
import TuistLoader
import TuistSupport

public final class MockTemplateLoader: TemplateLoading {
    public var loadTemplateStub: ((AbsolutePath, Versions) throws -> Template)?
    public func loadTemplate(at path: AbsolutePath, versions: Versions) throws -> Template {
        try loadTemplateStub?(path, versions) ?? Template(description: "", attributes: [], files: [])
    }
}
