import Foundation
import TSCBasic
@testable import TuistGraph

public extension Arguments {
    static func test(environment: [String: String] = [:],
                     launchArguments: [LaunchArgument] = []) -> Arguments
    {
        Arguments(
            environment: environment,
            launchArguments: launchArguments
        )
    }
}
