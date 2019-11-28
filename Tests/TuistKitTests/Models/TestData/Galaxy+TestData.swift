import Basic
import Foundation
import TuistSupport

@testable import TuistKit

extension Galaxy {
    static func test(token: String = "xyz") -> Galaxy {
        return Galaxy(token: token)
    }
}
