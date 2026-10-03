#if os(macOS)
    import ArgumentParser
    import TuistEnvKey
    import TuistSupport

    enum DependencyInspectionOutputFormat: String, CaseIterable, ExpressibleByArgument {
        case text
        case summary
        case json
    }

    struct InspectDependenciesCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "dependencies",
                abstract: "Inspects implicit and redundant dependencies in Tuist projects, failing when issues are found."
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
            help: "Run only specified checks. Can be repeated. Default: \(DependencyInspectionType.implicit.defaultValueDescription).",
            envKey: .inspectDependenciesOnly
        )
        var only: [DependencyInspectionType] = []

        @Option(
            name: .long,
            help: "The output format. Available options: \(DependencyInspectionOutputFormat.allCases.map(\.rawValue).joined(separator: ", "))."
        )
        var output: DependencyInspectionOutputFormat = .text

        @Flag(
            name: .long,
            help: "Output the result as JSON. Alias for '--output json'."
        )
        var json: Bool = false

        @OptionGroup
        var loggingOptions: LoggingOptions

        func run() async throws {
            let inspectionTypes: Set<DependencyInspectionType> = if only.isEmpty {
                Set(DependencyInspectionType.allCases)
            } else {
                Set(only)
            }

            try await InspectDependenciesCommandService()
                .run(
                    path: path,
                    inspectionTypes: inspectionTypes,
                    output: json ? .json : output
                )
        }
    }
#endif
