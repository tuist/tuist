import Foundation
import TSCBasic

struct MeasureResult {
    var fixture: String
    var coldRuns: [TimeInterval]
    var warmRuns: [TimeInterval]
}

enum MeasureError: LocalizedError {
    case commandFailed(command: [String])
    var errorDescription: String? {
        switch self {
        case let .commandFailed(command):
            return "Command returned non 0 exit code '\(command.joined(separator: " "))'"
        }
    }
}

final class Measure {
    private let fileHandler: FileHandler
    private let binaryPath: AbsolutePath

    init(
        fileHandler: FileHandler,
        binaryPath: AbsolutePath
    ) {
        self.fileHandler = fileHandler
        self.binaryPath = binaryPath
    }

    func measure(
        runs: Int,
        arguments: [String],
        fixturePath: AbsolutePath
    ) throws -> MeasureResult {
        let cold = try measureColdRuns(runs: runs, arguments: arguments, fixturePath: fixturePath)
        let warm = try measureWarmRuns(runs: runs, arguments: arguments, fixturePath: fixturePath)
        return MeasureResult(
            fixture: fixturePath.basename,
            coldRuns: cold,
            warmRuns: warm
        )
    }

    private func measureColdRuns(
        runs: Int,
        arguments: [String],
        fixturePath: AbsolutePath
    ) throws -> [TimeInterval] {
        try (0 ..< runs).map { _ in
            try withTemporaryDirectory(removeTreeOnDeinit: true) { temporaryDirectoryPath in
                let temporaryPath = temporaryDirectoryPath.appending(component: "fixture")
                try fileHandler.copy(path: fixturePath, to: temporaryPath)
                return try measure {
                    try run(
                        arguments: arguments,
                        in: temporaryPath
                    )
                }
            }
        }
    }

    private func measureWarmRuns(
        runs: Int,
        arguments: [String],
        fixturePath: AbsolutePath
    ) throws -> [TimeInterval] {
        try withTemporaryDirectory(removeTreeOnDeinit: true) { temporaryDirectoryPath in
            let temporaryPath = temporaryDirectoryPath.appending(component: "fixture")
            try fileHandler.copy(path: fixturePath, to: temporaryPath)

            // first warm up isn't included in the results
            try run(
                arguments: arguments,
                in: temporaryPath
            )

            return try measure(runs: runs) {
                try run(
                    arguments: arguments,
                    in: temporaryPath
                )
            }
        }
    }

    private func run(arguments: [String], in path: AbsolutePath) throws {
        let process = Process()
        process.executableURL = binaryPath.asURL
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.currentDirectoryPath = path.pathString
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MeasureError.commandFailed(command: [binaryPath.basename] + arguments)
        }
    }

    private func measure(runs: Int, code: () throws -> Void) throws -> [TimeInterval] {
        try (0 ..< runs).map { _ in
            try measure(code: code)
        }
    }

    private func measure(code: () throws -> Void) throws -> TimeInterval {
        let start = Date()
        try code()
        return Date().timeIntervalSince(start)
    }
}
