import Foundation
import TSCBasic
@testable import TuistGraph

public extension Arguments {
    static func test(environmentVariables: [EnvironmentVariable] = [],
                     launchArguments: [LaunchArgument] = []) -> Arguments
    {
        Arguments(
            environmentVariables: environmentVariables,
            launchArguments: launchArguments
        )
    }
}
