import Foundation
import TSCBasic
@testable import TuistGraph

extension PluginResourceSynthesizer {
    public static func test(
        name: String = "Plugin",
        path: AbsolutePath = AbsolutePath("/test")
    ) -> Self {
        .init(
            name: name,
            path: path
        )
    }
}
