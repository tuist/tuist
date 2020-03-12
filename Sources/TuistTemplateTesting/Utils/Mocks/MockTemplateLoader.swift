import Basic
import Foundation
import TuistTemplate

public final class MockTemplateLoader: TemplateLoading {
    public var loadTemplateStub: ((AbsolutePath) throws -> Template)?
    public var loadGenerateFileStub: ((AbsolutePath, [ParsedAttribute]) throws -> String)?
    public func loadTemplate(at path: AbsolutePath) throws -> Template {
        try loadTemplateStub?(path) ?? Template(description: "", attributes: [], files: [], directories: [])
    }

    public func loadGenerateFile(at path: AbsolutePath, parsedAttributes: [ParsedAttribute]) throws -> String {
        try loadGenerateFileStub?(path, parsedAttributes) ?? ""
    }
}
