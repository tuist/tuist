import Foundation
import TSCBasic

struct BenchmarkResult {
    var fixture: String
    var times: [TimeInterval]
    var referenceTimes: [TimeInterval]

    var delta: TimeInterval {
        times.average() - referenceTimes.average()
    }
}

final class Benchmark {
    private let fileHandler: FileHandler
    private let binaryPath: AbsolutePath
    private let referenceBinaryPath: AbsolutePath

    init(fileHandler: FileHandler,
         binaryPath: AbsolutePath,
         referenceBinaryPath: AbsolutePath) {
        self.fileHandler = fileHandler
        self.binaryPath = binaryPath
        self.referenceBinaryPath = referenceBinaryPath
    }

    func benchmark(runs: Int,
                   arguments: [String],
                   fixturePath: AbsolutePath) throws -> BenchmarkResult {
        let a = Measure(fileHandler: fileHandler, binaryPath: binaryPath)
        let b = Measure(fileHandler: fileHandler, binaryPath: referenceBinaryPath)

        let resultsA = try a.measure(runs: runs, arguments: arguments, fixturePath: fixturePath)
        let resultsB = try b.measure(runs: runs, arguments: arguments, fixturePath: fixturePath)

        return BenchmarkResult(fixture: fixturePath.basename,
                               times: resultsA.times,
                               referenceTimes: resultsB.times)
    }
}
