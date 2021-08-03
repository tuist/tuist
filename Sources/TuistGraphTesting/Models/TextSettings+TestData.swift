import Foundation
@testable import TuistGraph

public extension TextSettings {
    static func test(
        usesTabs: Bool? = true,
        indentWidth: UInt? = 2,
        tabWidth: UInt? = 2,
        wrapsLines: Bool? = true
    ) -> TextSettings {
        TextSettings(
            usesTabs: usesTabs,
            indentWidth: indentWidth,
            tabWidth: tabWidth,
            wrapsLines: wrapsLines
        )
    }
}
