#if os(macOS)
    import Foundation
    import Noora
    import Path
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistKit
    import TuistLoader
    import TuistLogging
    import TuistSupport
    import XcodeGraph

    struct InspectDependenciesCommandService {
        private let configLoader: ConfigLoading
        private let generatorFactory: GeneratorFactorying
        private let graphImportsLinter: GraphImportsLinting

        init(
            generatorFactory: GeneratorFactorying = GeneratorFactory(),
            configLoader: ConfigLoading = ConfigLoader(),
            graphImportsLinter: GraphImportsLinting = GraphImportsLinter()
        ) {
            self.configLoader = configLoader
            self.generatorFactory = generatorFactory
            self.graphImportsLinter = graphImportsLinter
        }

        func run(
            path: String?,
            inspectionTypes: Set<DependencyInspectionType>,
            output: DependencyInspectionOutputFormat = .text
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
            let config = try await configLoader.loadConfig(path: path)
            let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
            let graph = try await generator.load(
                path: path,
                options: config.project.generatedProject?.generationOptions
            )
            let graphTraverser = GraphTraverser(graph: graph)

            var implicitIssues: [InspectImportsIssue] = []
            var redundantIssues: [InspectImportsIssue] = []
            var checksRun: [String] = []

            if inspectionTypes.contains(.implicit) {
                implicitIssues = try await collectImplicitIssues(graphTraverser: graphTraverser)
                checksRun.append("implicit")
            }

            if inspectionTypes.contains(.redundant) {
                redundantIssues = try await collectRedundantIssues(
                    graphTraverser: graphTraverser,
                    ignoreTagsMatching: config.inspectOptions.redundantDependencies.ignoreTagsMatching
                )
                checksRun.append("redundant")
            }

            switch output {
            case .json:
                try Noora.current.json(
                    results(implicitIssues: implicitIssues, redundantIssues: redundantIssues)
                )

                if !implicitIssues.isEmpty || !redundantIssues.isEmpty {
                    throw DependencyInspectionFormattedIssuesFoundError()
                }
            case .summary:
                let results = results(implicitIssues: implicitIssues, redundantIssues: redundantIssues)
                if results.isEmpty {
                    Noora.current.passthrough("No dependency issues found.")
                    return
                }

                Noora.current.passthrough(
                    TerminalText(stringLiteral: results.map(\.summary).joined(separator: "\n"))
                )
                throw DependencyInspectionFormattedIssuesFoundError()
            case .text:
                if !implicitIssues.isEmpty || !redundantIssues.isEmpty {
                    throw InspectImportsServiceError.issuesFound(implicit: implicitIssues, redundant: redundantIssues)
                }

                Logger.current.log(
                    level: .info,
                    "We did not find any dependency issues in your project (checked: \(checksRun.joined(separator: ", ")))."
                )
            }
        }

        private func collectImplicitIssues(graphTraverser: GraphTraverser) async throws -> [InspectImportsIssue] {
            try await graphImportsLinter.lint(
                graphTraverser: graphTraverser,
                inspectType: .implicit,
                ignoreTagsMatching: []
            )
        }

        private func collectRedundantIssues(
            graphTraverser: GraphTraverser,
            ignoreTagsMatching: Set<String>
        ) async throws -> [InspectImportsIssue] {
            try await graphImportsLinter.lint(
                graphTraverser: graphTraverser,
                inspectType: .redundant,
                ignoreTagsMatching: ignoreTagsMatching
            )
        }

        private func results(
            implicitIssues: [InspectImportsIssue],
            redundantIssues: [InspectImportsIssue]
        ) -> [DependencyInspectionResult] {
            var resultsByTarget: [String: DependencyInspectionResult] = [:]

            for issue in implicitIssues {
                resultsByTarget[issue.target, default: .init(target: issue.target)].implicit = issue.dependencies.sorted()
            }
            for issue in redundantIssues {
                resultsByTarget[issue.target, default: .init(target: issue.target)].redundant = issue.dependencies.sorted()
            }

            return resultsByTarget.values.sorted { $0.target < $1.target }
        }
    }

    private struct DependencyInspectionResult: Codable {
        let target: String
        var implicit: [String]?
        var redundant: [String]?

        var summary: String {
            var lines = ["\(target):"]
            if let implicit {
                lines.append("  implicit: \(implicit.joined(separator: ", "))")
            }
            if let redundant {
                lines.append("  redundant: \(redundant.joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        }
    }

    struct DependencyInspectionFormattedIssuesFoundError: FatalError, Equatable {
        let description = ""
        let type = ErrorType.abortSilent
    }
#endif
