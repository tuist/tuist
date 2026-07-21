import Testing

@testable import TuistHTTP

struct HTTPRetryPolicyTests {
    @Test func uses_defaults_when_environment_is_empty() {
        let subject = HTTPRetryPolicy(environment: [:])

        #expect(subject.maximumRetryCount == 3)
        #expect(subject.baseDelayMilliseconds == 100)
    }

    @Test func uses_environment_overrides() {
        let subject = HTTPRetryPolicy(environment: [
            "TUIST_HTTP_MAXIMUM_RETRY_COUNT": "1",
            "TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS": "250",
        ])

        #expect(subject.maximumRetryCount == 1)
        #expect(subject.baseDelayMilliseconds == 250)
    }

    @Test func accepts_zero_retries_and_zero_delay() {
        let subject = HTTPRetryPolicy(environment: [
            "TUIST_HTTP_MAXIMUM_RETRY_COUNT": "0",
            "TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS": "0",
        ])

        #expect(subject.maximumRetryCount == 0)
        #expect(subject.delay(for: 0) == 0)
    }

    @Test func falls_back_to_defaults_for_invalid_environment_values() {
        let subject = HTTPRetryPolicy(environment: [
            "TUIST_HTTP_MAXIMUM_RETRY_COUNT": "-1",
            "TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS": "not-a-number",
        ])

        #expect(subject.maximumRetryCount == 3)
        #expect(subject.baseDelayMilliseconds == 100)
    }

    @Test func applies_exponential_backoff_and_jitter() {
        let subject = HTTPRetryPolicy(baseDelayMilliseconds: 100, environment: [:])

        for _ in 0 ... 20 {
            #expect((UInt64(100_000_000) ... UInt64(200_000_000)).contains(subject.delay(for: 0)))
            #expect((UInt64(200_000_000) ... UInt64(300_000_000)).contains(subject.delay(for: 1)))
            #expect((UInt64(400_000_000) ... UInt64(500_000_000)).contains(subject.delay(for: 2)))
        }
    }
}
