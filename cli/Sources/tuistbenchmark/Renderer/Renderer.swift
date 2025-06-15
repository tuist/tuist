import Foundation

protocol Renderer {
    func render(results: [MeasureResult])
    func render(results: [BenchmarkResult])
}

// MARK: -

extension Renderer {
    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.roundingMode = .halfUp
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter
    }

    func format(_ double: Double) -> String {
        formatter.string(for: double) ?? ""
    }

    func delta(
        first: TimeInterval,
        second: TimeInterval,
        threshold: TimeInterval
    ) -> String {
        let delta = first - second
        let prefix = delta > 0 ? "+" : ""
        let percentageString = prefix + format((delta / second) * 100)
        let deltaString = prefix + format(delta)

        if delta > threshold {
            return "⬆︎ \(deltaString)s \(percentageString)%"
        } else if delta < -threshold {
            return "⬇︎ \(deltaString)s \(percentageString)%"
        } else {
            return "≈"
        }
    }
}
