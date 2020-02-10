import Foundation

final class ConsoleRenderer: Renderer {
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
        results.forEach(render)
    }

    func render(results: [BenchmarkResult]) {
        results.forEach(render)
    }

    private func render(result: MeasureResult) {
        let first = result.times.first.map { format($0) } ?? ""
        let average = format(result.times.average())

        print("""

            Fixture       : \(result.fixture)
            Runs          : \(result.times.count)
            Result
                - initial : \(first)s
                - average : \(average)s

        """)
    }

    private func render(result: BenchmarkResult) {
        let first = result.times.first.map { format($0) } ?? ""
        let average = format(result.times.average())

        let referenceFirst = result.referenceTimes.first.map { format($0) } ?? ""
        let referenceAverage = format(result.referenceTimes.average())

        let deltaFirst = Array(zip(result.times, result.referenceTimes)).first.map(delta) ?? ""
        let deltaAverage = delta(first: result.times.average(), second: result.referenceTimes.average())

        print("""

            Fixture       : \(result.fixture)
            Runs          : \(result.times.count)
            Result
                - initial : \(first)s  vs  \(referenceFirst)s (\(deltaFirst))
                - average : \(average)s  vs  \(referenceAverage)s (\(deltaAverage))

        """)
    }

    private func delta(first: TimeInterval, second: TimeInterval) -> String {
        let delta = first - second
        let percentageString = format((abs(delta) / second) * 100)
        let deltaString = format(abs(delta))

        if delta > deltaThreshold {
            return "⬆︎ \(deltaString)s \(percentageString)%"
        } else if delta < -deltaThreshold {
            return "⬇︎ \(deltaString)s \(percentageString)%"
        } else {
            return "≈"
        }
    }

    private func format(_ double: Double) -> String {
        formatter.string(for: double) ?? ""
    }
}
