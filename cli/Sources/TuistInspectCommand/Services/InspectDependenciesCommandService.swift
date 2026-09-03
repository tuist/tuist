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
            json: Bool = false
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

            if json {
                try Noora.current.json(
                    jsonResults(implicitIssues: implicitIssues, redundantIssues: redundantIssues)
                )

                if !implicitIssues.isEmpty || !redundantIssues.isEmpty {
                    throw DependencyInspectionJSONIssuesFoundError()
                }
                return
            }

            if !implicitIssues.isEmpty || !redundantIssues.isEmpty {
                throw InspectImportsServiceError.issuesFound(implicit: implicitIssues, redundant: redundantIssues)
            }

            Logger.current.log(
                level: .info,
                "We did not find any dependency issues in your project (checked: \(checksRun.joined(separator: ", ")))."
            )
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

        private func jsonResults(
            implicitIssues: [InspectImportsIssue],
            redundantIssues: [InspectImportsIssue]
        ) -> [DependencyInspectionJSONResult] {
            var resultsByTarget: [String: DependencyInspectionJSONResult] = [:]

            for issue in implicitIssues {
                resultsByTarget[issue.target, default: .init(target: issue.target)].implicit = issue.dependencies.sorted()
            }
            for issue in redundantIssues {
                resultsByTarget[issue.target, default: .init(target: issue.target)].redundant = issue.dependencies.sorted()
            }

            return resultsByTarget.values.sorted { $0.target < $1.target }
        }
    }

    private struct DependencyInspectionJSONResult: Codable {
        let target: String
        var implicit: [String]?
        var redundant: [String]?
    }

    struct DependencyInspectionJSONIssuesFoundError: FatalError, Equatable {
        let description = ""
        let type = ErrorType.abortSilent
    }
#endif
