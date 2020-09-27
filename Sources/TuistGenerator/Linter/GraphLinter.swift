import Foundation
import struct TSCUtility.Version
import TuistCore
import TuistSupport

public protocol GraphLinting: AnyObject {
    func lint(graph: Graph) -> [LintingIssue]
}

// swiftlint:disable type_body_length
public class GraphLinter: GraphLinting {
    // MARK: - Attributes

    private let projectLinter: ProjectLinting
    private let staticProductsLinter: StaticProductsGraphLinting

    // MARK: - Init

    public convenience init() {
        let projectLinter = ProjectLinter()
        let staticProductsLinter = StaticProductsGraphLinter()
        self.init(projectLinter: projectLinter,
                  staticProductsLinter: staticProductsLinter)
    }

    init(projectLinter: ProjectLinting,
         staticProductsLinter: StaticProductsGraphLinting)
    {
        self.projectLinter = projectLinter
        self.staticProductsLinter = staticProductsLinter
    }

    // MARK: - GraphLinting

    public func lint(graph: Graph) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: graph.projects.flatMap { project -> [LintingIssue] in
            projectLinter.lint(project)
        })
        issues.append(contentsOf: lintDependencies(graph: graph))
        issues.append(contentsOf: lintMismatchingConfigurations(graph: graph))
        issues.append(contentsOf: lintWatchBundleIndentifiers(graph: graph))
        return issues
    }

    // MARK: - Fileprivate

    func lintDependencies(graph: Graph) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        var evaluatedNodes: [GraphNode] = []
        graph.entryNodes.forEach {
            issues.append(contentsOf: lintGraphNode(node: $0,
                                                    evaluatedNodes: &evaluatedNodes))
        }

        issues.append(contentsOf: staticProductsLinter.lint(graph: graph))
        issues.append(contentsOf: lintCarthageDependencies(graph: graph))
        issues.append(contentsOf: lintCocoaPodsDependencies(graph: graph))
        issues.append(contentsOf: lintPackageDependencies(graph: graph))

        return issues
    }

    private func lintGraphNode(node: GraphNode,
                               evaluatedNodes: inout [GraphNode]) -> [LintingIssue]
    {
        var issues: [LintingIssue] = []
        defer { evaluatedNodes.append(node) }

        if evaluatedNodes.contains(node) { return issues }
        guard let targetNode = node as? TargetNode else { return issues }

        targetNode.dependencies.forEach { toNode in
            if let toTargetNode = toNode as? TargetNode {
                issues.append(contentsOf: lintDependency(from: targetNode,
                                                         to: toTargetNode))
            }
            issues.append(contentsOf: lintGraphNode(node: toNode,
                                                    evaluatedNodes: &evaluatedNodes))
        }

        return issues
    }

    private func lintDependency(from: TargetNode,
                                to: TargetNode) -> [LintingIssue]
    {
        var issues: [LintingIssue] = []

        let fromTarget = LintableTarget(platform: from.target.platform,
                                        product: from.target.product)
        let toTarget = LintableTarget(platform: to.target.platform,
                                      product: to.target.product)

        if !GraphLinter.validLinks.keys.contains(fromTarget) {
            let reason = "Target \(from.target.name) has a platform '\(from.target.platform)' and product '\(from.target.product)' invalid or not supported yet."
            let issue = LintingIssue(reason: reason, severity: .error)
            issues.append(issue)
        }
        let supportedTargets = GraphLinter.validLinks[fromTarget]

        if supportedTargets == nil || supportedTargets?.contains(toTarget) == false {
            let reason = "Target \(from.target.name) has a dependency with target \(to.target.name) of type \(to.target.product) for platform '\(to.target.platform)' which is invalid or not supported yet."
            let issue = LintingIssue(reason: reason, severity: .error)
            issues.append(issue)
        }

        return issues
    }

    private func lintMismatchingConfigurations(graph: Graph) -> [LintingIssue] {
        let entryNodeProjects = graph.entryNodes.compactMap { $0 as? TargetNode }.map { $0.project }

        let knownConfigurations = entryNodeProjects.reduce(into: Set()) {
            $0.formUnion(Set($1.settings.configurations.keys))
        }

        let projectBuildConfigurations = graph.projects.compactMap { project -> (name: String, buildConfigurations: Set<BuildConfiguration>)? in
            (name: project.name, buildConfigurations: Set(project.settings.configurations.keys))
        }

        let mismatchingBuildConfigurations = projectBuildConfigurations.filter {
            !knownConfigurations.isSubset(of: $0.buildConfigurations)
        }

        return mismatchingBuildConfigurations.map {
            let expectedConfigurations = knownConfigurations.sorted()
            let configurations = $0.buildConfigurations.sorted()
            let reason = "The project '\($0.name)' has missing or mismatching configurations. It has \(configurations), other projects have \(expectedConfigurations)"
            return LintingIssue(reason: reason,
                                severity: .warning)
        }
    }

    /// It verifies setup for packages
    ///
    /// - Parameter graph: Project graph.
    /// - Returns: Linting issues.
    private func lintPackageDependencies(graph: Graph) -> [LintingIssue] {
        let containsPackageDependency = graph.packages.count > 0

        guard containsPackageDependency else { return [] }

        let version: Version
        do {
            version = try XcodeController.shared.selectedVersion()
        } catch {
            return [LintingIssue(reason: "Could not determine Xcode version", severity: .error)]
        }

        if version.major < 11 {
            let reason = "The project contains a SwiftPM package dependency but the selected version of Xcode is not compatible. Need at least 11 but got \(version)"
            return [LintingIssue(reason: reason, severity: .error)]
        }

        return []
    }

    /// It verifies that the directory specified by the CocoaPods dependencies contains a Podfile file.
    ///
    /// - Parameter graph: Project graph.
    /// - Returns: Linting issues.
    private func lintCocoaPodsDependencies(graph: Graph) -> [LintingIssue] {
        graph.cocoapods.compactMap { node in
            let podfilePath = node.podfilePath
            if !FileHandler.shared.exists(podfilePath) {
                return LintingIssue(reason: "The Podfile at path \(podfilePath) referenced by some projects does not exist", severity: .error)
            }
            return nil
        }
    }

    private func lintCarthageDependencies(graph: Graph) -> [LintingIssue] {
        let frameworks = graph.frameworks
        let carthageFrameworks = frameworks.filter { $0.isCarthage }
        let nonCarthageFrameworks = frameworks.filter { !$0.isCarthage }

        let carthageIssues = carthageFrameworks
            .filter { !FileHandler.shared.exists($0.path) }
            .map { LintingIssue(reason: "Framework not found at path \($0.path.pathString). The path might be wrong or Carthage dependencies not fetched", severity: .warning) }
        let nonCarthageIssues = nonCarthageFrameworks
            .filter { !FileHandler.shared.exists($0.path) }
            .map { LintingIssue(reason: "Framework not found at path \($0.path.pathString)", severity: .error) }

        var issues: [LintingIssue] = []
        issues.append(contentsOf: carthageIssues)
        issues.append(contentsOf: nonCarthageIssues)

        return issues
    }

    private func lintWatchBundleIndentifiers(graph: Graph) -> [LintingIssue] {
        let apps = graph
            .targets.values
            .flatMap { targets -> [TargetNode] in
                targets.compactMap { target in
                    if target.target.product == .app { return target }
                    return nil
                }
            }

        let issues = apps.flatMap { app -> [LintingIssue] in
            let watchApps = watchAppsFor(targetNode: app, graph: graph)
            return watchApps.flatMap { watchApp -> [LintingIssue] in
                let watchAppIssues = lint(watchApp: watchApp, parentApp: app)
                let watchExtensions = watchExtensionsFor(targetNode: watchApp, graph: graph)
                let watchExtensionIssues = watchExtensions.flatMap { watchExtension in
                    lint(watchExtension: watchExtension, parentWatchApp: watchApp)
                }
                return watchAppIssues + watchExtensionIssues
            }
        }

        return issues
    }

    private func lint(watchApp: TargetNode, parentApp: TargetNode) -> [LintingIssue] {
        guard watchApp.target.bundleId.hasPrefix(parentApp.target.bundleId) else {
            return [
                LintingIssue(reason: """
                Watch app '\(watchApp.name)' bundleId: \(watchApp.target.bundleId) isn't prefixed with its parent's app '\(parentApp.target.bundleId)' bundleId '\(parentApp.target.bundleId)'
                """, severity: .error),
            ]
        }
        return []
    }

    private func lint(watchExtension: TargetNode, parentWatchApp: TargetNode) -> [LintingIssue] {
        guard watchExtension.target.bundleId.hasPrefix(parentWatchApp.target.bundleId) else {
            return [
                LintingIssue(reason: """
                Watch extension '\(watchExtension.name)' bundleId: \(watchExtension.target.bundleId) isn't prefixed with its parent's watch app '\(parentWatchApp.target.bundleId)' bundleId '\(parentWatchApp.target.bundleId)'
                """, severity: .error),
            ]
        }
        return []
    }

    private func watchAppsFor(targetNode: TargetNode, graph: Graph) -> [TargetNode] {
        graph.targetDependencies(path: targetNode.path,
                                 name: targetNode.name)
            .filter { $0.target.product == .watch2App }
    }

    private func watchExtensionsFor(targetNode: TargetNode, graph: Graph) -> [TargetNode] {
        graph.targetDependencies(path: targetNode.path,
                                 name: targetNode.name)
            .filter { $0.target.product == .watch2Extension }
    }

    struct LintableTarget: Equatable, Hashable {
        let platform: TuistCore.Platform
        let product: Product
    }

    static let validLinks: [LintableTarget: [LintableTarget]] = [
        // iOS products
        LintableTarget(platform: .iOS, product: .app): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .bundle),
            LintableTarget(platform: .iOS, product: .appExtension),
            LintableTarget(platform: .iOS, product: .messagesExtension),
            LintableTarget(platform: .iOS, product: .stickerPackExtension),
            LintableTarget(platform: .watchOS, product: .watch2App),
//            LintableTarget(platform: .watchOS, product: .watchApp),
        ],
        LintableTarget(platform: .iOS, product: .staticLibrary): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .staticFramework): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .dynamicLibrary): [
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .framework): [
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .unitTests): [
            LintableTarget(platform: .iOS, product: .app),
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .uiTests): [
            LintableTarget(platform: .iOS, product: .app),
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .bundle),
        ],
        LintableTarget(platform: .iOS, product: .appExtension): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        //        LintableTarget(platform: .iOS, product: .messagesApplication): [
//            LintableTarget(platform: .iOS, product: .messagesExtension),
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
        LintableTarget(platform: .iOS, product: .messagesExtension): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        LintableTarget(platform: .iOS, product: .stickerPackExtension): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        // macOS
        LintableTarget(platform: .macOS, product: .app): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .appExtension),
        ],
        LintableTarget(platform: .macOS, product: .staticLibrary): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .bundle),
        ],
        LintableTarget(platform: .macOS, product: .staticFramework): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .bundle),
        ],
        LintableTarget(platform: .macOS, product: .dynamicLibrary): [
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .bundle),
        ],
        LintableTarget(platform: .macOS, product: .framework): [
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .bundle),
        ],
        LintableTarget(platform: .macOS, product: .unitTests): [
            LintableTarget(platform: .macOS, product: .app),
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .macOS, product: .uiTests): [
            LintableTarget(platform: .macOS, product: .app),
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .macOS, product: .appExtension): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
        ],
        // tvOS
        LintableTarget(platform: .tvOS, product: .app): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .tvOS, product: .staticFramework),
            LintableTarget(platform: .tvOS, product: .bundle),
//            LintableTarget(platform: .tvOS, product: .tvExtension),
        ],
        LintableTarget(platform: .tvOS, product: .staticLibrary): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .staticFramework),
            LintableTarget(platform: .tvOS, product: .bundle),
        ],
        LintableTarget(platform: .tvOS, product: .staticFramework): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .staticFramework),
            LintableTarget(platform: .tvOS, product: .bundle),
        ],
        LintableTarget(platform: .tvOS, product: .dynamicLibrary): [
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .bundle),
        ],
        LintableTarget(platform: .tvOS, product: .framework): [
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .staticFramework),
            LintableTarget(platform: .tvOS, product: .bundle),
        ],
        LintableTarget(platform: .tvOS, product: .unitTests): [
            LintableTarget(platform: .tvOS, product: .app),
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .tvOS, product: .staticFramework),
        ],
        //        LintableTarget(platform: .tvOS, product: .tvExtension): [
//            LintableTarget(platform: .tvOS, product: .staticLibrary),
//            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
//            LintableTarget(platform: .tvOS, product: .framework),
//        ],
        // watchOS
//        LintableTarget(platform: .watchOS, product: .watchApp): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//            LintableTarget(platform: .watchOS, product: .watchExtension),
//        ],
        LintableTarget(platform: .watchOS, product: .watch2App): [
            LintableTarget(platform: .watchOS, product: .watch2Extension),
        ],
        LintableTarget(platform: .watchOS, product: .staticLibrary): [
            LintableTarget(platform: .watchOS, product: .staticLibrary),
            LintableTarget(platform: .watchOS, product: .staticFramework),
            LintableTarget(platform: .watchOS, product: .bundle),
        ],
        LintableTarget(platform: .watchOS, product: .staticFramework): [
            LintableTarget(platform: .watchOS, product: .staticLibrary),
            LintableTarget(platform: .watchOS, product: .staticFramework),
            LintableTarget(platform: .watchOS, product: .framework),
            LintableTarget(platform: .watchOS, product: .bundle),
        ],
        LintableTarget(platform: .watchOS, product: .dynamicLibrary): [
            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
            LintableTarget(platform: .watchOS, product: .bundle),
        ],
        LintableTarget(platform: .watchOS, product: .framework): [
            LintableTarget(platform: .watchOS, product: .staticLibrary),
            LintableTarget(platform: .watchOS, product: .framework),
            LintableTarget(platform: .watchOS, product: .staticFramework),
            LintableTarget(platform: .watchOS, product: .bundle),
        ],
        //        LintableTarget(platform: .watchOS, product: .watchExtension): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//        ],
        LintableTarget(platform: .watchOS, product: .watch2Extension): [
            LintableTarget(platform: .watchOS, product: .staticLibrary),
            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
            LintableTarget(platform: .watchOS, product: .framework),
            LintableTarget(platform: .watchOS, product: .staticFramework),
        ],
    ]
}
