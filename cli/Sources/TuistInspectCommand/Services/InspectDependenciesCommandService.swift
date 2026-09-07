#if os(macOS) || os(Linux)
    import Foundation
    import Path
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistGraphLoader
    import TuistLoader
    import TuistLogging
    import TuistSupport
    import XcodeGraph

    struct InspectDependenciesCommandService {
        private let configLoader: ConfigLoading
        private let projectGraphLoader: ProjectGraphLoading
        private let graphImportsLinter: GraphImportsLinting

        init(
            projectGraphLoader: ProjectGraphLoading = ProjectGraphLoader(),
            configLoader: ConfigLoading = ConfigLoader(),
            graphImportsLinter: GraphImportsLinting = GraphImportsLinter()
        ) {
            self.configLoader = configLoader
            self.projectGraphLoader = projectGraphLoader
            self.graphImportsLinter = graphImportsLinter
        }

        func run(
            path: String?,
            inspectionTypes: Set<DependencyInspectionType>
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
            let config = try await configLoader.loadConfig(path: path)
            let graph = try await projectGraphLoader.load(path: path, config: config)
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
    }
#endif
