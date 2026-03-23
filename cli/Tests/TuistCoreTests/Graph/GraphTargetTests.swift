import Foundation
import XcodeGraph
import Testing
@testable import TuistCore
@testable import TuistTesting

struct GraphTargetTests {
    @Test func test_comparable() {
        #expect(GraphTarget.test(target: Target.test(name: "a")) < GraphTarget.test(target: Target.test(name: "b")))
        #expect(!(GraphTarget.test(target: Target.test(name: "b")) < GraphTarget.test(target: Target.test(name: "a"))))
        #expect(
            GraphTarget.test(path: "/a", target: Target.test(name: "a")) < GraphTarget
                .test(path: "/b", target: Target.test(name: "a"))
        )
        #expect(
            !(GraphTarget.test(path: "/b", target: Target.test(name: "a")) < GraphTarget
                .test(path: "/a", target: Target.test(name: "a")))
        )
    }
}
