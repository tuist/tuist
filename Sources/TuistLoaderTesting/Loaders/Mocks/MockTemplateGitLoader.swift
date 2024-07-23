import Foundation
import Path
import TuistCore
import TuistLoader

public final class MockTemplateGitLoader: TemplateGitLoading {
    public var loadTemplateStub: ((String) throws -> Template)?
    public func loadTemplate(from templateURL: String, closure: @escaping (Template) async throws -> Void) async throws {
        let template = try loadTemplateStub?(templateURL) ?? Template(description: "", attributes: [], items: [])
        try await closure(template)
    }
}
