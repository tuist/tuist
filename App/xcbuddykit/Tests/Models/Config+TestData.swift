import Foundation
import Basic
@testable import xcbuddykit

extension Config {
    static func testData(path: AbsolutePath = AbsolutePath("/test/")) -> Config {
        return Config(path: path)
    }
}
