import Foundation
import XCTest

@testable import TuistSupport

final class ArrayExecutionContextTests: XCTestCase {
    func test_concurrentMap_success() {
        // Given
        let numbers = Array(0 ... 1000)
        let transform: (Int) -> String = { "Number \($0)" }

        // When
        let results = numbers.map(context: .concurrent, transform)

        // Then
        XCTAssertEqual(results, numbers.map(transform))
    }

    func test_concurrentMap_errors() throws {
        // Given
        let numbers = Array(0 ... 1000)
        let transform: (Int) throws -> String = {
            guard $0 % 100 == 0 else {
                throw TestError.someError
            }
            return "Number \($0)"
        }

        // When / Then
        XCTAssertThrowsSpecific(try numbers.map(context: .concurrent, transform), TestError.someError)
    }

    func test_concurrentForEach_success() {
        // Given
        let numbers = Array(0 ... 1000)
        var performedNumbers = Set<Int>()
        let queue = DispatchQueue(label: "TestQueue")
        let perform: (Int) -> Void = { number in
            queue.async {
                performedNumbers.insert(number)
            }
        }

        // When
        numbers.forEach(context: .concurrent, perform)

        // Then
        let resuls = queue.sync {
            performedNumbers
        }
        XCTAssertEqual(resuls, Set(numbers))
    }

    func test_concurrentForEach_error() {
        // Given
        let numbers = Array(0 ... 1000)
        let perform: (Int) throws -> Void = {
            guard $0 % 100 == 0 else {
                throw TestError.someError
            }
        }

        // When / Then
        XCTAssertThrowsSpecific(try numbers.forEach(context: .concurrent, perform), TestError.someError)
    }

    func test_concurrentMap_withMaxConcurrentTasks_preservesInputOrder() async throws {
        // Given: elements with variable async work to force out-of-order completion
        let elements = Array(0 ..< 50)

        // When: run multiple times to catch non-determinism
        for _ in 0 ..< 10 {
            let results = try await elements.concurrentMap(maxConcurrentTasks: 5) { element -> Int in
                // Reverse the delay so later elements finish first
                let delay = UInt64((50 - element) * 1_000_000) // nanoseconds
                try await Task.sleep(nanoseconds: delay)
                return element
            }

            // Then: results must match input order
            XCTAssertEqual(results, elements)
        }
    }

    func test_concurrentCompactMap_withMaxConcurrentTasks_preservesInputOrder() async throws {
        let elements = Array(0 ..< 50)

        for _ in 0 ..< 10 {
            let results = try await elements.concurrentCompactMap(maxConcurrentTasks: 5) { element -> Int? in
                let delay = UInt64((50 - element) * 1_000_000)
                try await Task.sleep(nanoseconds: delay)
                return element
            }

            XCTAssertEqual(results, elements)
        }
    }

    // MARK: - Helpers

    private enum TestError: Error {
        case someError
    }
}
