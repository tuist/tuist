import Foundation

final class ConsoleRenderer: Renderer {
    private let deltaThreshold: TimeInterval

    init(deltaThreshold: TimeInterval) {
        self.deltaThreshold = deltaThreshold
    }

    func render(results: [MeasureResult]) {
        results.forEach(render)
    }

    func render(results: [BenchmarkResult]) {
        results.forEach(render)
    }

    private func render(result: MeasureResult) {
        let cold = format(result.coldRuns.average())
        let warm = format(result.warmRuns.average())

        print("""

            Fixture       : \(result.fixture)
            Runs          : \(result.coldRuns.count)
            Result
                - cold : \(cold)s
                - warm : \(warm)s

        """)
    }

    private func render(result: BenchmarkResult) {
        let cold = format(result.results.coldRuns.average())
        let warm = format(result.results.warmRuns.average())

        let coldReference = format(result.reference.coldRuns.average())
        let warmReference = format(result.reference.warmRuns.average())

        let coldDelta = delta(
            first: result.results.coldRuns.average(),
            second: result.reference.coldRuns.average(),
            threshold: deltaThreshold
        )
        let warmDelta = delta(
            first: result.results.warmRuns.average(),
            second: result.reference.warmRuns.average(),
            threshold: deltaThreshold
        )

        print("""

            Fixture       : \(result.fixture)
            Runs          : \(result.results.coldRuns.count)
            Result
                - cold : \(cold)s  vs  \(coldReference)s (\(coldDelta))
                - warm : \(warm)s  vs  \(warmReference)s (\(warmDelta))

        """)
    }
}
