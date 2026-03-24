import Foundation
import Path
import Testing
@testable import TuistCore

struct GraphCircularDetectorTests {
    var subject: GraphCircularDetector

    init() {
        subject = GraphCircularDetector()
    }

    @Test mutating func cycleDetected_1() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")

        // When
        subject.start(from: a, to: b)
        subject.start(from: b, to: c)
        subject.start(from: c, to: a)

        // Then
        #expect(throws: GraphLoadingError.circularDependency([a, b, c])) { try subject.complete() }
    }

    @Test mutating func cycleDetected_2() throws {
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
        #expect(throws: (any Error).self) { try subject.complete() }
    }

    @Test mutating func cycleDetected_3() throws {
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
        #expect(throws: (any Error).self) { try subject.complete() }
    }

    @Test mutating func noCycleDetected_1() throws {
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
        try subject.complete()
    }

    @Test mutating func noCycleDetected_2() throws {
        // Given
        let a = node("a")
        let b = node("b")
        let c = node("c")

        // When
        subject.start(from: a, to: b)
        subject.start(from: c, to: b)
        subject.start(from: c, to: a)

        // Then
        try subject.complete()
    }

    @Test mutating func noCycleDetected_3() throws {
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
        try subject.complete()
    }

    @Test mutating func noCycleDetected_detachedGraphs() throws {
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
        try subject.complete()
    }

    @Test mutating func cycleDetected_detachedGraphs() throws {
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
        #expect(throws: GraphLoadingError.circularDependency([d, e, f])) { try subject.complete() }
    }

    private func node(_ name: String) -> GraphCircularDetectorNode {
        GraphCircularDetectorNode(path: try! AbsolutePath(validating: "/\(name)/"), name: name)
    }
}
