import Foundation
import TSCBasic
@testable import TuistCore

public extension Arguments {
    static func test(environment: [String: String] = [:],
                     launchArguments: [LaunchArgument] = []) -> Arguments {
        Arguments(environment: environment,
                  launchArguments: launchArguments)
    }
}
