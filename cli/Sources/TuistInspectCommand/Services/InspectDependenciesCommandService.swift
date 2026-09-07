#if os(macOS)
    import Foundation
    import Path
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistKit
    import TuistLoader
    import TuistLogging
    import TuistSupport
    import XcodeGraph
    import XcodeGraphMapper

    struct InspectDependenciesCommandService {
        private let configLoader: ConfigLoading
        private let generatorFactory: GeneratorFactorying
        private let graphImportsLinter: GraphImportsLinting
        private let manifestLoader: ManifestLoading
        private let xcodeGraphMapper: XcodeGraphMapping
        private let localPackageProductsMapper: LocalPackageProductsMapping

        init(
            generatorFactory: GeneratorFactorying = GeneratorFactory(),
            configLoader: ConfigLoading = ConfigLoader(),
            graphImportsLinter: GraphImportsLinting = GraphImportsLinter(),
            manifestLoader: ManifestLoading = ManifestLoader.current,
            xcodeGraphMapper: XcodeGraphMapping = XcodeGraphMapper(),
            localPackageProductsMapper: LocalPackageProductsMapping = LocalPackageProductsMapper()
        ) {
            self.configLoader = configLoader
            self.generatorFactory = generatorFactory
            self.graphImportsLinter = graphImportsLinter
            self.manifestLoader = manifestLoader
            self.xcodeGraphMapper = xcodeGraphMapper
            self.localPackageProductsMapper = localPackageProductsMapper
        }

        func run(
            path: String?,
            inspectionTypes: Set<DependencyInspectionType>
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
            let config = try await configLoader.loadConfig(path: path)
            let isGeneratedProject = try await manifestLoader.hasRootManifest(at: path)
            let graph: XcodeGraph.Graph
            if isGeneratedProject {
                let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
                graph = try await generator.load(
                    path: path,
                    options: config.project.generatedProject?.generationOptions
                )
            } else {
                graph = try await xcodeGraphMapper.map(at: path)
            }
            let graphTraverser = GraphTraverser(graph: graph)

            var implicitIssues: [InspectImportsIssue] = []
            var redundantIssues: [InspectImportsIssue] = []
            var checksRun: [String] = []

            if inspectionTypes.contains(.implicit) {
                let implicitGraph = isGeneratedProject ? graph : try await localPackageProductsMapper.map(
                    graph: graph,
                    disableSandbox: config.project.disableSandbox
                )
                implicitIssues = try await collectImplicitIssues(
                    graphTraverser: isGeneratedProject ? graphTraverser : GraphTraverser(graph: implicitGraph)
                )
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
