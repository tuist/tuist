import Foundation
import MockableTest
import TuistSupportTesting
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
}
