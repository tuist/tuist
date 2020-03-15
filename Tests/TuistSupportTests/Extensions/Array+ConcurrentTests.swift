import Foundation
import XCTest

@testable import TuistSupport

final class ArrayConcurrentTests: XCTestCase {
    func test_concurrentMap_success() {
        // Given
        let numbers = Array(0 ... 1000)
        let transform: (Int) -> String = { "Number \($0)" }

        // When
        let results = numbers.concurrentMap(transform)

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
        XCTAssertThrowsSpecific(try numbers.concurrentMap(transform), TestError.someError)
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
        numbers.concurrentForEach(perform)

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
        XCTAssertThrowsSpecific(try numbers.concurrentForEach(perform), TestError.someError)
    }

    // MARK: - Helpers

    private enum TestError: Error {
        case someError
    }
}
