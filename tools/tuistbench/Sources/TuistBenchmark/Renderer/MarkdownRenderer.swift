import Foundation

final class MarkdownRenderer: Renderer {
    private let deltaThreshold: TimeInterval
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.roundingMode = .halfUp
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter
    }()

    init(deltaThreshold: TimeInterval) {
        self.deltaThreshold = deltaThreshold
    }

    func render(results: [MeasureResult]) {
        let rows = results.flatMap(render)

        print("""

        | Fixture            | Initial     | Average |
        | ------------------ | ----------- | ------- |
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
        let first = result.times.first.map { format($0) } ?? ""
        let average = format(result.times.average())

        return [
            "| \(result.fixture)  | \(first)s  | \(average)s |",
        ]
    }

    private func render(result: BenchmarkResult) -> [String] {
        let first = result.times.first.map { format($0) } ?? ""
        let average = format(result.times.average())

        let referenceFirst = result.referenceTimes.first.map { format($0) } ?? ""
        let referenceAverage = format(result.referenceTimes.average())

        let deltaFirst = Array(zip(result.times, result.referenceTimes)).first.map(delta) ?? ""
        let deltaAverage = delta(first: result.times.average(), second: result.referenceTimes.average())

        let runs = "\(result.times.count)x"
        return [
            "| \(result.fixture) _(initial)_           | \(first)s     | \(referenceFirst)s   | \(deltaFirst)   |",
            "| \(result.fixture) _(average - \(runs))_ | \(average)s   | \(referenceAverage)s | \(deltaAverage) |",
        ]
    }

    private func delta(first: TimeInterval, second: TimeInterval) -> String {
        let delta = first - second
        let percentageString = format((abs(delta) / second) * 100)

        if delta > deltaThreshold {
            return "⬆︎ \(percentageString)%"
        } else if delta < -deltaThreshold {
            return "⬇︎ \(percentageString)%"
        } else {
            return "≈"
        }
    }

    private func format(_ double: Double) -> String {
        formatter.string(for: double) ?? ""
    }
}
