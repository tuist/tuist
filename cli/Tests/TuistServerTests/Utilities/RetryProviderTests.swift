import Foundation
import Mockable
import Testing
import TuistTesting

@testable import TuistServer

struct RetryProviderTests {
    private let subject: RetryProviding
    init() {
        let delayProvider = MockDelayProviding()
        given(delayProvider)
            .delay(for: .any)
            .willReturn(1)
        subject = RetryProvider(
            delayProvider: delayProvider
        )
    }

    @Test
    func exists_whenSucceeds_doesNotRetry() async throws {
        // Given / When
        let operationCalls = Counter()
        try await subject.runWithRetries {
            operationCalls.increment()
        }

        // Then
        #expect(operationCalls.value == 1)
    }

    @Test
    func exists_whenFails_retries() async throws {
        // Given / When
        let operationCalls = Counter()
        try await subject.runWithRetries {
            operationCalls.increment()
            if operationCalls.value < 3 {
                throw TestError("exists failed")
            }
        }

        // Then
        #expect(operationCalls.value == 3)
    }

    @Test
    func exists_whenFailsFourTimes_throws() async throws {
        // Given
        let error = TestError("exists failed")
        let operationCalls = Counter()

        // When
        await #expect(throws: error) { try await subject.runWithRetries {
            operationCalls.increment()
            throw error
        } }

        // Then
        #expect(operationCalls.value == 4)
    }
}

private final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}
