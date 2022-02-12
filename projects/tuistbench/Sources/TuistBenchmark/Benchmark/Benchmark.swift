import Foundation
import TSCBasic

struct BenchmarkResult {
    var fixture: String
    var results: MeasureResult
    var reference: MeasureResult

    var coldRunsDelta: TimeInterval {
        results.coldRuns.average() - reference.coldRuns.average()
    }

    var warmRunsDelta: TimeInterval {
        results.warmRuns.average() - reference.warmRuns.average()
    }
}

final class Benchmark {
    private let fileHandler: FileHandler
    private let binaryPath: AbsolutePath
    private let referenceBinaryPath: AbsolutePath

    init(
        fileHandler: FileHandler,
        binaryPath: AbsolutePath,
        referenceBinaryPath: AbsolutePath
    ) {
        self.fileHandler = fileHandler
        self.binaryPath = binaryPath
        self.referenceBinaryPath = referenceBinaryPath
    }

    func benchmark(
        runs: Int,
        arguments: [String],
        fixturePath: AbsolutePath
    ) throws -> BenchmarkResult {
        let a = Measure(fileHandler: fileHandler, binaryPath: binaryPath)
        let b = Measure(fileHandler: fileHandler, binaryPath: referenceBinaryPath)

        let results = try a.measure(runs: runs, arguments: arguments, fixturePath: fixturePath)
        let reference = try b.measure(runs: runs, arguments: arguments, fixturePath: fixturePath)

        return BenchmarkResult(
            fixture: fixturePath.basename,
            results: results,
            reference: reference
        )
    }
}
