import Foundation
import TSCBasic
@testable import TuistGraph

extension Arguments {
    public static func test(
        environment: [String: String] = [:],
        launchArguments: [LaunchArgument] = []
    ) -> Arguments {
        Arguments(
            environment: environment,
            launchArguments: launchArguments
        )
    }
}
