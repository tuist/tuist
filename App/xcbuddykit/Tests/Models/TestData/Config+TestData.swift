import Basic
import Foundation
@testable import xcbuddykit

extension Config {
    static func testData(path: AbsolutePath = AbsolutePath("/test/")) -> Config {
        return Config(path: path)
    }
}
