import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistDependencies
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSigning
import TuistSupport
import Stencil

public protocol Generating {
    @discardableResult
    func load(path: AbsolutePath) async throws -> Graph
    func generate(path: AbsolutePath) async throws -> AbsolutePath
    func generateWithGraph(path: AbsolutePath) async throws -> (AbsolutePath, Graph)
}

public class Generator: Generating {
    private let graphLinter: GraphLinting = GraphLinter()
    private let environmentLinter: EnvironmentLinting = EnvironmentLinter()
    private let generator: DescriptorGenerating = DescriptorGenerator()
    private let writer: XcodeProjWriting = XcodeProjWriter()
    private let swiftPackageManagerInteractor: TuistGenerator.SwiftPackageManagerInteracting = TuistGenerator
        .SwiftPackageManagerInteractor()
    private let signingInteractor: SigningInteracting = SigningInteractor()
    private let sideEffectDescriptorExecutor: SideEffectDescriptorExecuting
    private let configLoader: ConfigLoading
    private let manifestGraphLoader: ManifestGraphLoading
    private var lintingIssues: [LintingIssue] = []

    public init(
        manifestLoader: ManifestLoading,
        manifestGraphLoader: ManifestGraphLoading
    ) {
        sideEffectDescriptorExecutor = SideEffectDescriptorExecutor()
        configLoader = ConfigLoader(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: RootDirectoryLocator(),
            fileHandler: FileHandler.shared
        )
        self.manifestGraphLoader = manifestGraphLoader
    }

    public func generate(path: AbsolutePath) async throws -> AbsolutePath {
        let (generatedPath, _) = try await generateWithGraph(path: path)
        return generatedPath
    }

    struct PodFileData: Codable {
        let targetsPods: [TargetsPod]
        struct TargetsPod: Codable {
            let targetName: String
            let projectName: String
            let podsList: [String]
            let hasTestTarget: Bool
        }
    }

    public func generateWithGraph(path: AbsolutePath) async throws -> (AbsolutePath, Graph) {
        let (graph, sideEffects) = try await load(path: path)

        var isPodfileUpdated = false
        if GenerateCommandHelper.generatePodfile {
            logger.notice("Generating Podfile")
            var targetsPods = [PodFileData.TargetsPod]()

            func fetchTargetPods(targetName: String) -> [String] {
                if targetsPods.contains(where: { $0.targetName == targetName }) {
                    return targetsPods.filter { $0.targetName == targetName }.first?.podsList ?? [String]()
                } else {
                    var resultPods = [String]()
                    for (projectAbsolutePath, targets) in graph.targets {
                        for (currentTargetName, target) in targets where currentTargetName == targetName {
                            for dependency in target.dependencies {
                                switch dependency {
                                case .cocoapod(_, let content):
                                    resultPods.append(content)
                                case .target(let childTargetName, _) where GenerateCommandHelper.recursivelyFindCocoapodsDependencies:
                                    resultPods.append(contentsOf: fetchTargetPods(targetName: childTargetName))
                                case .project(let childTargetName, _, _) where GenerateCommandHelper.recursivelyFindCocoapodsDependencies:
                                    resultPods.append(contentsOf: fetchTargetPods(targetName: childTargetName))
                                default:
                                    continue
                                }
                            }
                            resultPods = Array(Set(resultPods)).sorted()
                            targetsPods.append(
                                .init(
                                    targetName: currentTargetName,
                                    projectName: graph.projects[projectAbsolutePath]?.name ?? "",
                                    podsList: resultPods,
                                    hasTestTarget: targets.values.contains { $0.name == "\(targetName)Tests" }
                                )
                            )
                        }
                    }
                    return resultPods
                }
            }

            for (_, targets) in graph.targets {
                for (targetName, target) in targets {
                    switch target.product {
                    case .unitTests, .bundle:
                        continue
                    default:
                        _ = fetchTargetPods(targetName: targetName)
                    }
                }
            }
            targetsPods = targetsPods.filter { !$0.podsList.isEmpty }.sorted { $0.targetName < $1.targetName }
            let podFileData = PodFileData(targetsPods: targetsPods)
            if
                let data = try? JSONEncoder().encode(podFileData),
                let context = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
            {
                let currentDirectoryPath = FileHandler.shared.currentPath.pathString
                let fileSystemLoader = FileSystemLoader(paths: [.init(currentDirectoryPath)])
                let environment = Environment(loader: fileSystemLoader)
                if let output = try? environment.renderTemplate(name: "Podfile.stencil", context: context) {
                    let outputPath = currentDirectoryPath + "/Podfile"
                    let url = URL(fileURLWithPath: outputPath)
                    let pastOutput = try? String(contentsOf: url, encoding: .utf8)
                    if pastOutput != output {
                        logger.notice("Writing Podfile")
                        isPodfileUpdated = true
                        try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
                    }
                }
            }
        }

        // Load
        let graphTraverser = GraphTraverser(graph: graph)

        // Lint
        try lint(graphTraverser: graphTraverser)

        // Generate
        let workspaceDescriptor = try generator.generateWorkspace(graphTraverser: graphTraverser)

        // Write
        try writer.write(workspace: workspaceDescriptor)

        // Mapper side effects
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)

        // Post Generate Actions
        try await postGenerationActions(
            graphTraverser: graphTraverser,
            workspaceName: workspaceDescriptor.xcworkspacePath.basename
        )

        printAndFlushPendingLintWarnings()

        if isPodfileUpdated && GenerateCommandHelper.autoPodInstall {
            logger.notice("Pod install")
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", "bundle exec pod install"]
            task.launch()
            task.waitUntilExit()
            logger.notice("Pod install finished")
        }
        logger.notice("Generating finished")

        return (workspaceDescriptor.xcworkspacePath, graph)
    }

    public func load(path: AbsolutePath) async throws -> Graph {
        try await load(path: path).0
    }

    func load(path: AbsolutePath) async throws -> (Graph, [SideEffectDescriptor]) {
        let (graph, sideEffectDescriptors, issues) = try await manifestGraphLoader.load(path: path)
        lintingIssues.append(contentsOf: issues)
        return (graph, sideEffectDescriptors)
    }

    private func lint(graphTraverser: GraphTraversing) throws {
        let config = try configLoader.loadConfig(path: graphTraverser.path)

        let environmentIssues = try environmentLinter.lint(config: config)
        try environmentIssues.printAndThrowErrorsIfNeeded()
        lintingIssues.append(contentsOf: environmentIssues)

        let graphIssues = graphLinter.lint(graphTraverser: graphTraverser, config: config)
        try graphIssues.printAndThrowErrorsIfNeeded()
        lintingIssues.append(contentsOf: graphIssues)
    }

    private func postGenerationActions(graphTraverser: GraphTraversing, workspaceName: String) async throws {
        let config = try configLoader.loadConfig(path: graphTraverser.path)

        lintingIssues.append(contentsOf: try signingInteractor.install(graphTraverser: graphTraverser))
        try await swiftPackageManagerInteractor.install(
            graphTraverser: graphTraverser,
            workspaceName: workspaceName,
            config: config
        )
    }

    private func printAndFlushPendingLintWarnings() {
        // Print out warnings, if any
        lintingIssues.printWarningsIfNeeded()
        lintingIssues.removeAll()
    }
}
