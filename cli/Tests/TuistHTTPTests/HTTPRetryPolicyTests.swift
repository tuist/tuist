import Testing

@testable import TuistHTTP

struct HTTPRetryPolicyTests {
    @Test func uses_defaults_when_environment_is_empty() {
        let subject = HTTPRetryPolicy(environment: [:])

        #expect(subject.maximumRetryCount == 4)
        #expect(subject.baseDelayMilliseconds == 200)
    }

    @Test(arguments: [400, 401, 402, 403, 404, 409, 422])
    func client_errors_are_permanent(statusCode: Int) {
        #expect(HTTPRetryPolicy.isPermanentClientError(statusCode: statusCode))
    }

    @Test(arguments: [408, 429, 500, 502, 503, 504])
    func retryable_status_codes_are_not_permanent(statusCode: Int) {
        #expect(!HTTPRetryPolicy.isPermanentClientError(statusCode: statusCode))
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

        #expect(subject.maximumRetryCount == 4)
        #expect(subject.baseDelayMilliseconds == 200)
    }

    @Test func clamps_extreme_environment_values_to_safe_limits() {
        let subject = HTTPRetryPolicy(environment: [
            "TUIST_HTTP_MAXIMUM_RETRY_COUNT": String(Int.max),
            "TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS": String(UInt64.max),
        ])

        #expect(subject.maximumRetryCount == HTTPRetryPolicy.maximumRetryCountLimit)
        #expect(subject.baseDelayMilliseconds == HTTPRetryPolicy.maximumDelayMilliseconds)
    }

    @Test func caps_computed_delays() {
        let subject = HTTPRetryPolicy(baseDelayMilliseconds: 100, environment: [:])
        let maximumDelayNanoseconds = HTTPRetryPolicy.maximumDelayMilliseconds * 1_000_000

        #expect(subject.delay(for: 9) == maximumDelayNanoseconds)
        #expect(subject.delay(for: .max) == maximumDelayNanoseconds)
    }

    @Test func applies_exponential_backoff_and_jitter() {
        let subject = HTTPRetryPolicy(baseDelayMilliseconds: 100, environment: [:])

        for _ in 0 ... 20 {
            #expect((UInt64(100_000_000) ... UInt64(200_000_000)).contains(subject.delay(for: 0)))
            #expect((UInt64(200_000_000) ... UInt64(300_000_000)).contains(subject.delay(for: 1)))
            #expect((UInt64(400_000_000) ... UInt64(500_000_000)).contains(subject.delay(for: 2)))
        }
    }

    @Test func default_ladder_waits_a_few_seconds_in_total() {
        let subject = HTTPRetryPolicy(environment: [:])

        for _ in 0 ... 20 {
            let total = (0 ..< subject.maximumRetryCount).reduce(UInt64(0)) { $0 + subject.delay(for: $1) }
            #expect((UInt64(3_000_000_000) ... UInt64(3_800_000_000)).contains(total))
        }
    }

    @Test func uses_caller_defaults_when_environment_is_empty() {
        let subject = HTTPRetryPolicy(
            defaultMaximumRetryCount: 3,
            defaultBaseDelayMilliseconds: 100,
            environment: [:]
        )

        #expect(subject.maximumRetryCount == 3)
        #expect(subject.baseDelayMilliseconds == 100)
    }

    @Test func environment_overrides_caller_defaults() {
        let subject = HTTPRetryPolicy(
            defaultMaximumRetryCount: 3,
            defaultBaseDelayMilliseconds: 100,
            environment: [
                "TUIST_HTTP_MAXIMUM_RETRY_COUNT": "1",
                "TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS": "250",
            ]
        )

        #expect(subject.maximumRetryCount == 1)
        #expect(subject.baseDelayMilliseconds == 250)
    }
}
