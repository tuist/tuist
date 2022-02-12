import Foundation
import TSCBasic
@testable import TuistGraph

extension Template {
    public static func test(
        description: String = "Template",
        attributes: [Attribute] = [],
        items: [Template.Item] = []
    ) -> Template {
        Template(
            description: description,
            attributes: attributes,
            items: items
        )
    }
}

extension Template.Item {
    public static func test(
        path: RelativePath,
        contents: Template.Contents = .string("test content")
    ) -> Template.Item {
        Template.Item(
            path: path,
            contents: contents
        )
    }
}
