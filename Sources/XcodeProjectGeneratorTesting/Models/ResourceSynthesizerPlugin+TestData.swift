import Foundation
import TSCBasic
@testable import XcodeProjectGenerator

extension PluginResourceSynthesizer {
    public static func test(
        name: String = "Plugin",
        path: AbsolutePath = try! AbsolutePath(validating: "/test") // swiftlint:disable:this force_try
    ) -> Self {
        .init(
            name: name,
            path: path
        )
    }
}
