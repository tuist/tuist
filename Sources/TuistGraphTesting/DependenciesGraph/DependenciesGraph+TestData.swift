import Foundation
import TSCBasic
import TuistGraph

public extension DependenciesGraph {
    static func test(
        thirdPartyDependencies: [String: ThirdPartyDependency] = [:]
    ) -> Self {
        .init(
            thirdPartyDependencies: thirdPartyDependencies
        )
    }
}
