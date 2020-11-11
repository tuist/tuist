import Foundation
import TSCBasic
@testable import TuistCore

public extension Plugin {
    static func test(name: String = "TestPlugin") -> Plugin {
        Plugin.helpers(name: name)
    }
}
