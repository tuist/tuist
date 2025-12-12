import ArgumentParser
import TuistSupport

struct InspectDependenciesCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "dependencies",
            abstract: "Find implicit and redundant dependencies in Tuist projects, failing when issues are found."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project.",
        completion: .directory,
        envKey: .inspectDependenciesPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Run only specified checks. Can be repeated. Options: implicit, redundant. Default: all checks.",
        envKey: .inspectDependenciesOnly
    )
    var only: [DependencyInspectionType] = []

    func run() async throws {
        let inspectionTypes: Set<DependencyInspectionType> = if only.isEmpty {
            Set(DependencyInspectionType.allCases)
        } else {
            Set(only)
        }

        try await InspectDependenciesService()
            .run(path: path, inspectionTypes: inspectionTypes)
    }
}
