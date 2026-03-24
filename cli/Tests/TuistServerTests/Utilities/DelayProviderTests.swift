import Foundation
import Testing
import TuistTesting

@testable import TuistServer

struct DelayProviderTests {
    private let subject: DelayProviding
    init() {
        subject = DelayProvider()
    }

    @Test
    func delay_for_first_retry() {
        for _ in 0 ... 20 {
            #expect(
                (UInt64(0) ... UInt64(2_000_000)).contains(subject.delay(for: 0))
            )
        }
    }

    @Test
    func delay_for_second_retry() {
        for _ in 0 ... 20 {
            #expect(
                (UInt64(1_000_000) ... UInt64(3_000_000)).contains(subject.delay(for: 1))
            )
        }
    }

    @Test
    func delay_for_third_retry() {
        for _ in 0 ... 20 {
            #expect(
                (UInt64(3_000_000) ... UInt64(5_000_000)).contains(subject.delay(for: 2))
            )
        }
    }
}
