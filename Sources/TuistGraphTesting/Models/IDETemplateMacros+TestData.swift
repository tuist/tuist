import Foundation
import TuistGraph
import TuistSupportTesting

public extension IDETemplateMacros {
    static func test(fileHeader: String? = "Header template") -> IDETemplateMacros {
        IDETemplateMacros(fileHeader: fileHeader)
    }
}
