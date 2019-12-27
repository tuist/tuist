import Basic
import Foundation
import TuistSupport

@testable import TuistLoader

extension Galaxy {
    static func test(token: String = "xyz") -> Galaxy {
        Galaxy(token: token)
    }
}
