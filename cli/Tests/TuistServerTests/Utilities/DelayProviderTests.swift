import Testing

@testable import TuistServer

struct DelayProviderTests {
    @Test func delay_for_first_retry() {
        let subject = DelayProvider(baseDelayMilliseconds: 100)

        for _ in 0 ... 20 {
            #expect((UInt64(100_000_000) ... UInt64(200_000_000)).contains(subject.delay(for: 0)))
        }
    }

    @Test func delay_for_second_retry() {
        let subject = DelayProvider(baseDelayMilliseconds: 100)

        for _ in 0 ... 20 {
            #expect((UInt64(200_000_000) ... UInt64(300_000_000)).contains(subject.delay(for: 1)))
        }
    }

    @Test func delay_for_third_retry() {
        let subject = DelayProvider(baseDelayMilliseconds: 100)

        for _ in 0 ... 20 {
            #expect((UInt64(400_000_000) ... UInt64(500_000_000)).contains(subject.delay(for: 2)))
        }
    }
}
