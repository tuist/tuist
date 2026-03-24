import Foundation
import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistTesting

struct GraphTargetTests {
    @Test func comparable() {
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
