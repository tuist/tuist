import Foundation
import Testing

@testable import MacFramework

struct MacFrameworkParallelizableTests {
    @Test
    func testHello() {
        let sut = MacFramework()

        #expect(sut.hello() == "MacFramework.hello()")
    }

    @Test
    func testWorld() {
        let sut = MacFramework()

        #expect(sut.world() == "MacFramework.world()")
    }
}
