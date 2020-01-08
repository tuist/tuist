import Basic
import Foundation
@testable import TuistCore

public extension Arguments {
    static func test(environment: [String: String] = [:],
                     launch: [String: Bool] = [:]) -> Arguments {
        Arguments(environment: environment,
                  launch: launch)
    }
}
