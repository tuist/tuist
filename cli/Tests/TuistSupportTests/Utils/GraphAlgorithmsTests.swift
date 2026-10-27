import XCTest

@testable import TuistSupport

final class GraphAlgorithmsTests: XCTestCase {
    func test_topologicalSort_returnsReversePostorder() throws {
        let graph = [
            "A": ["B", "C"],
            "B": ["D"],
            "C": ["D"],
            "D": [],
        ]

        let got = try topologicalSort(["A"]) { node in
            graph[node] ?? []
        }

        XCTAssertEqual(got, ["A", "C", "B", "D"])
    }

    func test_topologicalSort_ignoresAlreadyVisitedRoots() throws {
        let graph = [
            "A": ["B"],
            "B": [],
        ]

        let got = try topologicalSort(["A", "B", "A"]) { node in
            graph[node] ?? []
        }

        XCTAssertEqual(got, ["A", "B"])
    }

    func test_topologicalSort_throwsWhenCycleIsDetected() throws {
        let graph = [
            "A": ["B"],
            "B": ["C"],
            "C": ["A"],
        ]

        XCTAssertThrowsError(
            try topologicalSort(["A"]) { node in
                graph[node] ?? []
            }
        ) { error in
            guard let graphError = error as? GraphAlgorithmError,
                  case .unexpectedCycle = graphError
            else {
                XCTFail("Expected GraphAlgorithmError.unexpectedCycle, got \(error)")
                return
            }
        }
    }

    func test_topologicalSort_handlesLongChainsWithoutRecursion() throws {
        let nodeCount = 20000

        let got = try topologicalSort([0]) { node in
            node + 1 < nodeCount ? [node + 1] : []
        }

        XCTAssertEqual(got.count, nodeCount)
        XCTAssertEqual(got.first, 0)
        XCTAssertEqual(got.last, nodeCount - 1)
    }
}
