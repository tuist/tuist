import Foundation
import TSCBasic
@testable import TuistGraph

public extension PluginResourceSynthesizer {
    static func test(
        name: String = "Plugin",
        path: AbsolutePath = AbsolutePath("/test")
    ) -> Self {
        .init(
            name: name,
            path: path
        )
    }
}
