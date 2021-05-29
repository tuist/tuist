import Foundation

struct BenchmarkConfig: Decodable {
    /// Arguments to use when running the binary (e.g. `generate`)
    var arguments: [String]

    /// Number of runs to performs (final results are the average of all those runs)
    var runs: Int

    /// The time interval threshold that must be exceeded to record a delta
    /// any measurements below this threshold are treated as ≈
    var deltaThreshold: TimeInterval

    /// Default benchmarking configuration
    static var `default`: BenchmarkConfig {
        BenchmarkConfig(
            arguments: ["generate"],
            runs: 5,
            deltaThreshold: 0.02
        )
    }
}
