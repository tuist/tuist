import Foundation
import TSCBasic
@testable import TuistCore

extension Template {
    public static func test(description: String = "Template",
                            attributes: [Template.Attribute] = [],
                            files: [Template.File] = []) -> Template
    {
        Template(description: description,
                 attributes: attributes,
                 files: files)
    }
}

extension Template.File {
    public static func test(path: RelativePath,
                            contents: Template.Contents = .string("test content")) -> Template.File
    {
        Template.File(path: path,
                      contents: contents)
    }
}
