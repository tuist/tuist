import Foundation

final class MarkdownRenderer: Renderer {
    private let deltaThreshold: TimeInterval
    init(deltaThreshold: TimeInterval) {
        self.deltaThreshold = deltaThreshold
    }

    func render(results: [MeasureResult]) {
        let rows = results.flatMap(render)

        print("""

        | Fixture            | Cold | Warm |
        | ------------------ | ---- | ---- |
        \(rows.joined(separator: "\n"))

        """)
    }

    func render(results: [BenchmarkResult]) {
        let rows = results.flatMap(render)

        print("""

        | Fixture         | New    | Old  | Delta    |
        | --------------- | ------ | ---- | -------- |
        \(rows.joined(separator: "\n"))

        """)
    }

    private func render(result: MeasureResult) -> [String] {
        let cold = format(result.coldRuns.average())
        let warm = format(result.warmRuns.average())

        return [
            "| \(result.fixture)  | \(cold)s  | \(warm)s |",
        ]
    }

    private func render(result: BenchmarkResult) -> [String] {
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

        return [
            "| \(result.fixture) _(cold)_ | \(cold)s | \(coldReference)s | \(coldDelta) |",
            "| \(result.fixture) _(warm)_ | \(warm)s | \(warmReference)s | \(warmDelta) |",
        ]
    }
}
