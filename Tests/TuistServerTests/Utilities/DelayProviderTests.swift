import Foundation
import TuistSupportTesting
import XCTest

@testable import TuistServer

final class DelayProviderTests: TuistUnitTestCase {
    private var subject: DelayProviding!

    override func setUp() {
        super.setUp()

        subject = DelayProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_delay_for_first_retry() {
        for _ in 0 ... 20 {
            XCTAssertTrue(
                (UInt64(0) ... UInt64(2_000_000)).contains(subject.delay(for: 0))
            )
        }
    }

    func test_delay_for_second_retry() {
        for _ in 0 ... 20 {
            XCTAssertTrue(
                (UInt64(1_000_000) ... UInt64(3_000_000)).contains(subject.delay(for: 1))
            )
        }
    }

    func test_delay_for_third_retry() {
        for _ in 0 ... 20 {
            XCTAssertTrue(
                (UInt64(3_000_000) ... UInt64(5_000_000)).contains(subject.delay(for: 2))
            )
        }
    }
}
