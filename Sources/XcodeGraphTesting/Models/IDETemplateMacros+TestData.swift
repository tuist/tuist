import Foundation
import TuistSupportTesting
import XcodeGraph

extension IDETemplateMacros {
    public static func test(fileHeader: String? = "Header template") -> IDETemplateMacros {
        IDETemplateMacros(fileHeader: fileHeader)
    }
}
