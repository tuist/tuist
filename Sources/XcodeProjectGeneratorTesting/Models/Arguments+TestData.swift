import Foundation
import TSCBasic
@testable import XcodeProjectGenerator

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
