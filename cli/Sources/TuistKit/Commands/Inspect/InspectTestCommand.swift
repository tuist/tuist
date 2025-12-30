import ArgumentParser
import Foundation

struct InspectTestCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Inspects the latest test results."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to inspect the latest test results for.",
        completion: .directory,
        envKey: .inspectTestPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "The path to the directory containing the project's derived data artifacts.",
        completion: .directory,
        envKey: .inspectTestDerivedDataPath
    )
    var derivedDataPath: String?

    @Argument(
        help: "The path to the result bundle (.xcresult) to inspect. If not provided, the most recent result bundle from the derived data directory will be used.",
        completion: .file(extensions: ["xcresult"]),
        envKey: .inspectTestResultBundlePath
    )
    var resultBundlePath: String?

    var jsonThroughNoora: Bool = false

    func run() async throws {
        try await InspectTestCommandService()
            .run(
                path: path,
                derivedDataPath: derivedDataPath,
                resultBundlePath: resultBundlePath
            )
    }
}
