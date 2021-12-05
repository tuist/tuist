import Foundation
import TuistGraph
import TuistSupportTesting

extension IDETemplateMacros {
    public static func test(fileHeader: String? = "Header template") -> IDETemplateMacros {
        IDETemplateMacros(fileHeader: fileHeader)
    }
}
