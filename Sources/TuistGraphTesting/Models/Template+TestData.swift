import Foundation
import TSCBasic
@testable import TuistGraph

public extension Template {
    static func test(description: String = "Template",
                     attributes: [Attribute] = [],
                     items: [Template.Item] = []) -> Template
    {
        Template(
            description: description,
            attributes: attributes,
            items: items
        )
    }
}

public extension Template.Item {
    static func test(path: RelativePath,
                     contents: Template.Contents = .string("test content")) -> Template.Item
    {
        Template.Item(
            path: path,
            contents: contents
        )
    }
}
