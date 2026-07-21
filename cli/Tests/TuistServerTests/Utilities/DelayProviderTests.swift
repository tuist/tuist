import Foundation
import TuistTesting
import XCTest

@testable import TuistServer

final class DelayProviderTests: TuistUnitTestCase {
    private var subject: DelayProviding!

    override func setUp() {
        super.setUp()

        subject = DelayProvider(baseDelayMilliseconds: 100)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_delay_for_first_retry() {
        for _ in 0 ... 20 {
            XCTAssertTrue(
                (UInt64(100_000_000) ... UInt64(200_000_000)).contains(subject.delay(for: 0))
            )
        }
    }

    func test_delay_for_second_retry() {
        for _ in 0 ... 20 {
            XCTAssertTrue(
                (UInt64(200_000_000) ... UInt64(300_000_000)).contains(subject.delay(for: 1))
            )
        }
    }

    func test_delay_for_third_retry() {
        for _ in 0 ... 20 {
            XCTAssertTrue(
                (UInt64(400_000_000) ... UInt64(500_000_000)).contains(subject.delay(for: 2))
            )
        }
    }
}
