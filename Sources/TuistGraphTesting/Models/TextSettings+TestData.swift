import Foundation
@testable import TuistGraph

public extension TextSettings {
    static func test(indentWidth: UInt? = 2, tabWidth: UInt? = 2) -> TextSettings {
        TextSettings(usesTabs: true, indentWidth: indentWidth, tabWidth: tabWidth, wrapsLines: true)
    }
}
