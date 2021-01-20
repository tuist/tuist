import Foundation
import TSCBasic
import XCTest
import TuistGraph
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class ValueGraphTargetTests: TuistUnitTestCase {
    func test_comparable() {
        XCTAssertTrue(ValueGraphTarget.test(target: Target.test(name: "a")) < ValueGraphTarget.test(target: Target.test(name: "b")))
        XCTAssertFalse(ValueGraphTarget.test(target: Target.test(name: "b")) < ValueGraphTarget.test(target: Target.test(name: "a")))
        XCTAssertTrue(ValueGraphTarget.test(path: "/a", target: Target.test(name: "a")) < ValueGraphTarget.test(path: "/b", target: Target.test(name: "a")))
        XCTAssertFalse(ValueGraphTarget.test(path: "/b", target: Target.test(name: "a")) < ValueGraphTarget.test(path: "/a", target: Target.test(name: "a")))
    }
}
