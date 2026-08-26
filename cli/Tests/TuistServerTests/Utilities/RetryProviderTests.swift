import Foundation
import Mockable
import Testing
import TuistHTTP
import TuistTesting
import TuistThreadSafe
import XCTest

@testable import TuistServer

final class RetryProviderTests: TuistUnitTestCase {
    private var operationCalls = 0
    private var subject: RetryProviding!

    override func setUp() {
        super.setUp()

        let delayProvider = MockDelayProviding()
        given(delayProvider)
            .delay(for: .any)
            .willReturn(1)

        subject = RetryProvider(
            maximumRetryCount: 3,
            delayProvider: delayProvider
        )
    }

    override func tearDown() {
        subject = nil
        operationCalls = 0
        super.tearDown()
    }

    func test_exists_whenSucceeds_doesNotRetry() async throws {
        // Given / When
        try await subject.runWithRetries { [self] in
            operationCalls += 1
        }

        // Then
        XCTAssertEqual(operationCalls, 1)
    }

    func test_exists_whenFails_retries() async throws {
        // Given / When
        try await subject.runWithRetries { [self] in
            operationCalls += 1
            if operationCalls < 3 {
                throw TestError("exists failed")
            }
        }

        // Then
        XCTAssertEqual(operationCalls, 3)
    }

    func test_exists_whenFailsFourTimes_throws() async throws {
        // Given
        let error = TestError("exists failed")

        // When
        await XCTAssertThrowsSpecific(
            try await subject.runWithRetries { [self] in
                operationCalls += 1
                throw error
            },
            error
        )

        // Then
        XCTAssertEqual(operationCalls, 4)
    }

    func test_runWithRetries_whenMaximumRetryCountIsZero_doesNotRetry() async throws {
        // Given
        let error = TestError("exists failed")
        let subject = RetryProvider(maximumRetryCount: 0)

        // When
        await XCTAssertThrowsSpecific(
            try await subject.runWithRetries { [self] in
                operationCalls += 1
                throw error
            },
            error
        )

        // Then
        XCTAssertEqual(operationCalls, 1)
    }

    func test_runWithRetries_whenOperationIsCancelled_doesNotRetry() async throws {
        // Given / When
        do {
            try await subject.runWithRetries { [self] in
                operationCalls += 1
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {}

        // Then
        XCTAssertEqual(operationCalls, 1)
    }

    func test_runWithRetries_whenCallerTaskIsCancelled_cancelsInFlightOperation() async throws {
        // Given
        let operationStarted = expectation(description: "Operation started")
        let task = Task {
            try await subject.runWithRetries {
                operationStarted.fulfill()
                try await Task.sleep(for: .seconds(2))
            }
        }
        await fulfillment(of: [operationStarted], timeout: 1)

        // When
        let cancellationStartedAt = Date()
        task.cancel()

        // Then
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(cancellationStartedAt), 0.5)
    }
}

struct RetryProviderErrorClassificationTests {
    private let subject: RetryProviding

    init() {
        let delayProvider = MockDelayProviding()
        given(delayProvider)
            .delay(for: .any)
            .willReturn(1)

        subject = RetryProvider(maximumRetryCount: 3, delayProvider: delayProvider)
    }

    @Test func does_not_retry_a_permanent_client_error() async throws {
        // Given
        let operationCalls = ThreadSafe(0)
        let error = GetCacheServiceError.forbidden("Not authorized to read cache")

        // When
        await #expect(throws: error) {
            try await subject.runWithRetries {
                operationCalls.mutate { $0 += 1 }
                throw error
            }
        }

        // Then
        #expect(operationCalls.value == 1)
    }

    @Test func does_not_retry_a_throttled_authorization_denial() async throws {
        // Given
        let operationCalls = ThreadSafe(0)
        let error = AuthorizationThrottledError(retryAfterSeconds: 30)

        // When
        await #expect(throws: error) {
            try await subject.runWithRetries {
                operationCalls.mutate { $0 += 1 }
                throw error
            }
        }

        // Then
        #expect(operationCalls.value == 1)
    }

    @Test func retries_a_retryable_server_error() async throws {
        // Given
        let operationCalls = ThreadSafe(0)
        let error = GetCacheServiceError.unknownError(503)

        // When
        await #expect(throws: error) {
            try await subject.runWithRetries {
                operationCalls.mutate { $0 += 1 }
                throw error
            }
        }

        // Then
        #expect(operationCalls.value == 4)
    }
}
