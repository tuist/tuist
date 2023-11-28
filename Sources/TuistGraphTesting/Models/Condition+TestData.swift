import Foundation
import TuistGraph
import XCTest

extension TargetDependency.Condition {
    static func test(_ platformFilters: PlatformFilters) throws -> TargetDependency.Condition {
        try XCTUnwrap(.when(platformFilters))
    }
}
