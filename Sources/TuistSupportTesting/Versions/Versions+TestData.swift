import Foundation
import SPMUtility
import TuistSupport

public extension Versions {
    static func test(xcode: Version = "11.4.0",
                     swift: Version = "5.2.0") -> Versions {
        Versions(xcode: xcode, swift: swift)
    }
}
