import FileSystem
import Foundation
import Path

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
    private let fileSystem: FileSysteming
    private let binaryPath: AbsolutePath
    private let referenceBinaryPath: AbsolutePath

    init(
        fileSystem: FileSysteming,
        binaryPath: AbsolutePath,
        referenceBinaryPath: AbsolutePath
    ) {
        self.fileSystem = fileSystem
        self.binaryPath = binaryPath
        self.referenceBinaryPath = referenceBinaryPath
    }

    func benchmark(
        runs: Int,
        arguments: [String],
        fixturePath: AbsolutePath
    ) async throws -> BenchmarkResult {
        let a = Measure(fileSystem: fileSystem, binaryPath: binaryPath)
        let b = Measure(fileSystem: fileSystem, binaryPath: referenceBinaryPath)

        let results = try await a.measure(runs: runs, arguments: arguments, fixturePath: fixturePath)
        let reference = try await b.measure(runs: runs, arguments: arguments, fixturePath: fixturePath)

        return BenchmarkResult(
            fixture: fixturePath.basename,
            results: results,
            reference: reference
        )
    }
}
