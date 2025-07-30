import ArgumentParser
import Foundation

struct InspectTestsCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tests",
            abstract: "Inspects the latest test results."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to inspect the latest test results for.",
        completion: .directory,
        envKey: .inspectTestsPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "The path to the directory containing the project's derived data artifacts.",
        completion: .directory,
        envKey: .inspectTestsDerivedDataPath
    )
    var derivedDataPath: String?

    func run() async throws {
//        try await InspectBuildCommandService()
//            .run(
//                path: path,
//                derivedDataPath: derivedDataPath
//            )
    }
}
