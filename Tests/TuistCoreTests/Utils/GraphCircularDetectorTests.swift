import Foundation
import TSCBasic
import XCTest
@testable import TuistCore

final class GraphCircularDetectorTests: XCTestCase {
    var subject: GraphCircularDetector!

    override func setUp() {
        super.setUp()
        subject = GraphCircularDetector()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_cycleDetected_1() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")

        // When
        subject.start(from: a, to: b)
        subject.start(from: b, to: c)
        subject.start(from: c, to: a)

        // Then
        XCTAssertThrowsSpecific(try subject.complete(), GraphLoadingError.circularDependency([a, b, c]))
    }

    func test_cycleDetected_2() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")
        let d = node("d")
        let e = node("e")

        // When
        subject.start(from: a, to: c)
        subject.start(from: c, to: d)
        subject.start(from: d, to: e)
        subject.start(from: e, to: b)
        subject.start(from: b, to: c)

        // Then
        XCTAssertThrowsError(try subject.complete())
    }

    func test_cycleDetected_3() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")
        let d = node("d")
        let e = node("e")

        // When
        subject.start(from: a, to: c)
        subject.start(from: c, to: d)
        subject.start(from: d, to: e)
        subject.start(from: d, to: b)
        subject.start(from: e, to: a)

        // Then
        XCTAssertThrowsError(try subject.complete())
    }

    func test_noCycleDetected_1() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")
        let d = node("d")

        // When
        subject.start(from: a, to: b)
        subject.start(from: b, to: c)
        subject.start(from: b, to: d)

        // Then
        XCTAssertNoThrow(try subject.complete())
    }

    func test_noCycleDetected_2() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")

        // When
        subject.start(from: a, to: b)
        subject.start(from: c, to: b)
        subject.start(from: c, to: a)

        // Then
        XCTAssertNoThrow(try subject.complete())
    }

    func test_noCycleDetected_3() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")
        let d = node("d")
        let e = node("e")

        // When
        subject.start(from: a, to: b)
        subject.start(from: a, to: c)
        subject.start(from: a, to: d)
        subject.start(from: a, to: e)

        subject.start(from: b, to: c)
        subject.start(from: b, to: d)
        subject.start(from: b, to: e)

        subject.start(from: c, to: d)
        subject.start(from: c, to: e)

        subject.start(from: d, to: e)

        // Then
        XCTAssertNoThrow(try subject.complete())
    }

    func test_noCycleDetected_detachedGraphs() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")
        let d = node("d")
        let e = node("e")

        // When
        subject.start(from: a, to: b)
        subject.start(from: a, to: c)
        subject.start(from: b, to: c)

        subject.start(from: d, to: e)

        // Then
        XCTAssertNoThrow(try subject.complete())
    }

    func test_cycleDetected_detachedGraphs() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")
        let d = node("d")
        let e = node("e")
        let f = node("f")

        // When
        subject.start(from: a, to: b)
        subject.start(from: a, to: c)
        subject.start(from: b, to: c)

        subject.start(from: d, to: e)
        subject.start(from: e, to: f)
        subject.start(from: f, to: d)

        // Then
        XCTAssertThrowsSpecific(try subject.complete(), GraphLoadingError.circularDependency([d, e, f]))
    }

    // MARK: -

    // MARK: - Performance

    func test_performance() throws {
        // ~ <200ms
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            // Given
            var nodes = (0 ..< 1000).map { node("\($0)") }.shuffled()

            while let node = nodes.popLast() {
                nodes.forEach {
                    subject.start(from: $0, to: node)
                }
            }

            // When / Then
            startMeasuring()
            do {
                try subject.complete()
            } catch {
                XCTFail()
            }
            stopMeasuring()
        }
    }

    private func node(_ name: String) -> GraphCircularDetectorNode {
        GraphCircularDetectorNode(path: try! AbsolutePath(validating: "/\(name)/"), name: name)
    }
}
