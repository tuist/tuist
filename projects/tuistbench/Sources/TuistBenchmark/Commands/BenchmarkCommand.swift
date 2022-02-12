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

enum BenchmarkResultFormat: String, CaseIterable, StringEnumArgument {
    case console
    case markdown

    static var completion: ShellCompletion {
        .values(
            BenchmarkResultFormat.allCases.map {
                (value: $0.rawValue, description: $0.rawValue)
            }
        )
    }
}

final class BenchmarkCommand {
    private let configPathOption: OptionArgument<PathArgument>
    private let formatOption: OptionArgument<BenchmarkResultFormat>
    private let fixtureListPathOption: OptionArgument<PathArgument>
    private let fixturePathOption: OptionArgument<PathArgument>
    private let binaryPathOption: OptionArgument<PathArgument>
    private let referenceBinaryPathOption: OptionArgument<PathArgument>

    private let fileHandler: FileHandler

    init(fileHandler: FileHandler, parser: ArgumentParser) {
        self.fileHandler = fileHandler
        configPathOption = parser.add(
            option: "--config",
            shortName: "-c",
            kind: PathArgument.self,
            usage: "The path to the benchmarking configuration json file.",
            completion: .filename
        )
        formatOption = parser.add(
            option: "--format",
            kind: BenchmarkResultFormat.self,
            usage: "The output format of the benchmark results."
        )
        fixtureListPathOption = parser.add(
            option: "--fixture-list",
            shortName: "-l",
            kind: PathArgument.self,
            usage: "The path to the fixtures list json file.",
            completion: .filename
        )
        fixturePathOption = parser.add(
            option: "--fixture",
            shortName: "-f",
            kind: PathArgument.self,
            usage: "The path to the fixture to user for benchmarking.",
            completion: .filename
        )
        binaryPathOption = parser.add(
            option: "--binary",
            shortName: "-b",
            kind: PathArgument.self,
            usage: "The path to the binary to benchmark.",
            completion: .filename
        )
        referenceBinaryPathOption = parser.add(
            option: "--reference-binary",
            shortName: "-r",
            kind: PathArgument.self,
            usage: "The path to the binary to use as a reference for the benchmark.",
            completion: .filename
        )
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let configPath = arguments.get(configPathOption)?.path
        let format = arguments.get(formatOption) ?? .console
        let fixturePath = arguments.get(fixturePathOption)?.path
        let fixtureListPath = arguments.get(fixtureListPathOption)?.path
        let referenceBinaryPath = arguments.get(referenceBinaryPathOption)?.path

        guard let binaryPath = arguments.get(binaryPathOption)?.path else {
            throw BenchmarkCommandError.missing(description: "binary path")
        }

        let config: BenchmarkConfig = try configPath.map(parseConfig) ?? .default
        let fixtures = try getFixturePaths(
            fixturesListPath: fixtureListPath,
            fixturePath: fixturePath
        )

        let renderer = makeRenderer(
            for: format,
            config: config
        )

        if let referenceBinaryPath = referenceBinaryPath {
            let results = try benchmark(
                config: config,
                fixtures: fixtures,
                binaryPath: binaryPath,
                referenceBinaryPath: referenceBinaryPath
            )
            renderer.render(results: results)
        } else {
            let results = try measure(
                config: config,
                fixtures: fixtures,
                binaryPath: binaryPath
            )
            renderer.render(results: results)
        }
    }

    private func measure(
        config: BenchmarkConfig,
        fixtures: [AbsolutePath],
        binaryPath: AbsolutePath
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
        referenceBinaryPath: AbsolutePath
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
        fixturePath: AbsolutePath?
    ) throws -> [AbsolutePath] {
        if let fixturePath = fixturePath {
            return [fixturePath]
        }

        if let fixturesListPath = fixturesListPath {
            let fixtures = try parseFixtureList(path: fixturesListPath)
            return fixtures.paths.map {
                AbsolutePath($0, relativeTo: fileHandler.currentPath)
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
        let data = try fileHandler.contents(of: path)
        return try decoder.decode(BenchmarkConfig.self, from: data)
    }

    private func parseFixtureList(path: AbsolutePath) throws -> Fixtures {
        let decoder = JSONDecoder()
        let data = try fileHandler.contents(of: path)
        return try decoder.decode(Fixtures.self, from: data)
    }
}
