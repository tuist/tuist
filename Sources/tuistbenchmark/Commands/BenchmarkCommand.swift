import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility

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

struct BenchmarkCommand: ParsableCommand {
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
        help: "The path to the fixture to user for benchmarking.",
        completion: .directory
    )
    var fixture: AbsolutePath
    
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

    func run() throws {
        let fileHandler = FileHandler()
        let config: BenchmarkConfig = try config.map({ try parseConfig(path: $0, fileHandler: fileHandler) }) ?? .default
        let fixtures = try getFixturePaths(
            fixturesListPath: fixtureList,
            fixturePath: fixture,
            fileHandler: fileHandler
        )

        let renderer = makeRenderer(
            for: format ?? .console,
            config: config
        )

        if let referenceBinary {
            let results = try benchmark(
                config: config,
                fixtures: fixtures,
                binaryPath: binary,
                referenceBinaryPath: referenceBinary,
                fileHandler: fileHandler
            )
            renderer.render(results: results)
        } else {
            let results = try measure(
                config: config,
                fixtures: fixtures,
                binaryPath: binary,
                fileHandler: fileHandler
            )
            renderer.render(results: results)
        }
    }

    private func measure(
        config: BenchmarkConfig,
        fixtures: [AbsolutePath],
        binaryPath: AbsolutePath,
        fileHandler: FileHandler
    ) throws -> [MeasureResult] {
        let measure = Measure(
            fileHandler: fileHandler,
            binaryPath: binaryPath
        )
        let results = try fixtures.map {
            try measure.measure(
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
        fileHandler: FileHandler
    ) throws -> [BenchmarkResult] {
        let benchmark = Benchmark(
            fileHandler: fileHandler,
            binaryPath: binaryPath,
            referenceBinaryPath: referenceBinaryPath
        )
        let results = try fixtures.map {
            try benchmark.benchmark(
                runs: config.runs,
                arguments: config.arguments,
                fixturePath: $0
            )
        }
        return results
    }

    private func getFixturePaths(
        fixturesListPath: AbsolutePath?,
        fixturePath: AbsolutePath?,
        fileHandler: FileHandler
    ) throws -> [AbsolutePath] {
        if let fixturePath {
            return [fixturePath]
        }

        if let fixturesListPath {
            let fixtures = try parseFixtureList(path: fixturesListPath, fileHandler: fileHandler)
            return try fixtures.paths.map {
                try AbsolutePath(validating: $0, relativeTo: fileHandler.currentPath)
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

    private func parseConfig(path: AbsolutePath, fileHandler: FileHandler) throws -> BenchmarkConfig {
        let decoder = JSONDecoder()
        let data = try fileHandler.contents(of: path)
        return try decoder.decode(BenchmarkConfig.self, from: data)
    }

    private func parseFixtureList(path: AbsolutePath, fileHandler: FileHandler) throws -> Fixtures {
        let decoder = JSONDecoder()
        let data = try fileHandler.contents(of: path)
        return try decoder.decode(Fixtures.self, from: data)
    }
}
