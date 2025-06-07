import ArgumentParser
import FileSystem
import Foundation
import Path
import TSCUtility
import TuistSupport

enum BenchmarkCommandError: LocalizedError {
    case missing(description: String)

    var errorDescription: String? {
        switch self {
        case let .missing(description: description):
            return "Missing \(description)."
        }
    }
}

enum BenchmarkResultFormat: String, CaseIterable, ExpressibleByArgument {
    case console
    case markdown
}

extension AbsolutePath: ExpressibleByArgument {
    public init?(argument: String) {
        guard let path = try? AbsolutePath(validating: argument) else {
            return nil
        }
        self = path
    }
}

struct BenchmarkCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "benchmark",
            abstract: "A utility to benchmark running tuist against a set of fixtures.",
            subcommands: []
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the benchmarking configuration json file.",
        completion: .file(extensions: ["json"])
    )
    var config: AbsolutePath?

    @Option(
        name: .shortAndLong,
        help: "The output format of the benchmark results."
    )
    var format: BenchmarkResultFormat?

    @Option(
        name: .shortAndLong,
        help: "The path to the fixtures list json file.",
        completion: .file(extensions: ["json"])
    )
    var fixtureList: AbsolutePath

    @Option(
        name: .shortAndLong,
        help: "The path to the fixture to use for benchmarking.",
        completion: .directory
    )
    var fixture: AbsolutePath?

    @Option(
        name: .shortAndLong,
        help: "The path to the binary to benchmark.",
        completion: .file()
    )
    var binary: AbsolutePath

    @Option(
        name: .shortAndLong,
        help: "The path to the binary to use as a reference for the benchmark.",
        completion: .file()
    )
    var referenceBinary: AbsolutePath?

    func run() async throws {
        let fileSystem = FileSystem()
        let config: BenchmarkConfig = try config.map { try parseConfig(path: $0) } ?? .default
        let fixtures = try await getFixturePaths(
            fixturesListPath: fixtureList,
            fixturePath: fixture
        )

        let renderer = makeRenderer(
            for: format ?? .console,
            config: config
        )

        if let referenceBinary {
            let results = try await benchmark(
                config: config,
                fixtures: fixtures,
                binaryPath: binary,
                referenceBinaryPath: referenceBinary,
                fileSystem: fileSystem
            )
            renderer.render(results: results)
        } else {
            let results = try await measure(
                config: config,
                fixtures: fixtures,
                binaryPath: binary,
                fileSystem: fileSystem
            )
            renderer.render(results: results)
        }
    }

    private func measure(
        config: BenchmarkConfig,
        fixtures: [AbsolutePath],
        binaryPath: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> [MeasureResult] {
        let measure = Measure(
            fileSystem: fileSystem,
            binaryPath: binaryPath
        )
        let results = try await fixtures.serialMap {
            try await measure.measure(
                runs: config.runs,
                arguments: config.arguments,
                fixturePath: $0
            )
        }
        return results
    }

    private func benchmark(
        config: BenchmarkConfig,
        fixtures: [AbsolutePath],
        binaryPath: AbsolutePath,
        referenceBinaryPath: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> [BenchmarkResult] {
        let benchmark = Benchmark(
            fileSystem: fileSystem,
            binaryPath: binaryPath,
            referenceBinaryPath: referenceBinaryPath
        )
        let results = try await fixtures.serialMap {
            try await benchmark.benchmark(
                runs: config.runs,
                arguments: config.arguments,
                fixturePath: $0
            )
        }
        return results
    }

    private func getFixturePaths(
        fixturesListPath: AbsolutePath?,
        fixturePath: AbsolutePath?
    ) async throws -> [AbsolutePath] {
        if let fixturePath {
            return [fixturePath]
        }

        if let fixturesListPath {
            let fixtures = try parseFixtureList(path: fixturesListPath)
            return try await fixtures.paths.serialMap {
                try AbsolutePath(validating: $0, relativeTo: try await Environment.current.currentWorkingDirectory())
            }
        }

        return []
    }

    private func makeRenderer(for option: BenchmarkResultFormat, config: BenchmarkConfig) -> Renderer {
        switch option {
        case .console:
            return ConsoleRenderer(deltaThreshold: config.deltaThreshold)
        case .markdown:
            return MarkdownRenderer(deltaThreshold: config.deltaThreshold)
        }
    }

    private func parseConfig(path: AbsolutePath) throws -> BenchmarkConfig {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: URL(string: path.pathString)!)
        return try decoder.decode(BenchmarkConfig.self, from: data)
    }

    private func parseFixtureList(path: AbsolutePath) throws -> Fixtures {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: URL(string: path.pathString)!)
        return try decoder.decode(Fixtures.self, from: data)
    }
}
