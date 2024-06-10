import Foundation
import Path
@testable import XcodeGraph

extension Arguments {
    public static func test(
        environmentVariables: [String: EnvironmentVariable] = [:],
        launchArguments: [LaunchArgument] = []
    ) -> Arguments {
        Arguments(
            environmentVariables: environmentVariables,
            launchArguments: launchArguments
        )
    }
}
