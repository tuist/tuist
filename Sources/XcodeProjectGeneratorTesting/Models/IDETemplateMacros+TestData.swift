import Foundation
import XcodeProjectGenerator
import TuistSupportTesting

extension IDETemplateMacros {
    public static func test(fileHeader: String? = "Header template") -> IDETemplateMacros {
        IDETemplateMacros(fileHeader: fileHeader)
    }
}
