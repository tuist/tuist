import Foundation
import PathKit
@testable import xcbuddykit

extension Config {
    static func testData(path: Path = Path("/test/")) -> Config {
        return Config(path: path)
    }
}
