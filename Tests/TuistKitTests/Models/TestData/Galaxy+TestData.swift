import Basic
import Foundation
import TuistSupport

@testable import TuistKit

extension Galaxy {
    static func test(token: String = "xyz") -> Galaxy {
        Galaxy(token: token)
    }
}
