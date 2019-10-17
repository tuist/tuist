import Foundation
import SPMUtility
import TuistCore

protocol GraphLinting: AnyObject {
    func lint(graph: Graphing) -> [LintingIssue]
}

// swiftlint:disable type_body_length
class GraphLinter: GraphLinting {
    // MARK: - Attributes

    let projectLinter: ProjectLinting

    // MARK: - Init

    init(projectLinter: ProjectLinting = ProjectLinter()) {
        self.projectLinter = projectLinter
    }

    struct StaticDepedencyWarning: Hashable {
        let fromTargetNode: TargetNode
        let toTargetNode: GraphNode

        func hash(into hasher: inout Hasher) {
            hasher.combine(toTargetNode)
        }

        static func == (lhs: StaticDepedencyWarning, rhs: StaticDepedencyWarning) -> Bool {
            return lhs.toTargetNode == rhs.toTargetNode
        }
    }

    // MARK: - GraphLinting

    func lint(graph: Graphing) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: graph.projects.flatMap(projectLinter.lint))
        issues.append(contentsOf: lintDependencies(graph: graph))
        issues.append(contentsOf: lintMismatchingConfigurations(graph: graph))
        return issues
    }

    // MARK: - Fileprivate

    func lintDependencies(graph: Graphing) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        var evaluatedNodes: [GraphNode] = []
        var linkedStaticProducts = Set<StaticDepedencyWarning>()
        graph.entryNodes.forEach {
            issues.append(contentsOf: lintGraphNode(node: $0,
                                                    evaluatedNodes: &evaluatedNodes,
                                                    linkedStaticProducts: &linkedStaticProducts))
        }

        issues.append(contentsOf: lintCarthageDependencies(graph: graph))
        issues.append(contentsOf: lintCocoaPodsDependencies(graph: graph))
        issues.append(contentsOf: lintPackageDependencies(graph: graph))

        return issues
    }

    private func lintGraphNode(node: GraphNode,
                               evaluatedNodes: inout [GraphNode],
                               linkedStaticProducts: inout Set<StaticDepedencyWarning>) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        defer { evaluatedNodes.append(node) }

        if evaluatedNodes.contains(node) { return issues }
        guard let targetNode = node as? TargetNode else { return issues }

        targetNode.dependencies.forEach { toNode in
            if let toTargetNode = toNode as? TargetNode {
                issues.append(contentsOf: lintDependency(from: targetNode,
                                                         to: toTargetNode,
                                                         linkedStaticProducts: &linkedStaticProducts))
            } else if let toPackageNode = toNode as? PackageNode {
                issues.append(contentsOf: lintPackageDependency(from: targetNode,
                                                                to: toPackageNode,
                                                                linkedStaticProducts: &linkedStaticProducts))
            }
            issues.append(contentsOf: lintGraphNode(node: toNode,
                                                    evaluatedNodes: &evaluatedNodes,
                                                    linkedStaticProducts: &linkedStaticProducts))
        }

        return issues
    }

    /// Package dependencies are also static products, so we need to perform the same check as for them
    private func lintPackageDependency(from: TargetNode,
                                       to: PackageNode,
                                       linkedStaticProducts: inout Set<StaticDepedencyWarning>) -> [LintingIssue] {
        guard from.target.canLinkStaticProducts() else {
            return []
        }
        let warning = StaticDepedencyWarning(fromTargetNode: from,
                                             toTargetNode: to)
        let (inserted, oldMember) = linkedStaticProducts.insert(warning)
        guard inserted == false else {
            return []
        }

        let reason = "Package \(to.name) has been linked against \(oldMember.fromTargetNode.target.name) and \(from.target.name), it is a static product so may introduce unwanted side effects."
        let issue = LintingIssue(reason: reason, severity: .warning)
        return [issue]
    }

    private func lintDependency(from: TargetNode,
                                to: TargetNode,
                                linkedStaticProducts: inout Set<StaticDepedencyWarning>) -> [LintingIssue] {
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
        let supportedTargets = GraphLinter.validLinks[fromTarget]!

        if !supportedTargets.contains(toTarget) {
            let reason = "Target \(from.target.name) has a dependency with target \(to.target.name) of type \(to.target.product) for platform '\(to.target.platform)' which is invalid or not supported yet."
            let issue = LintingIssue(reason: reason, severity: .error)
            issues.append(issue)
        }

        issues.append(contentsOf: lintStaticDependencies(from: from,
                                                         to: to,
                                                         linkedStaticProducts: &linkedStaticProducts))

        return issues
    }

    private func lintStaticDependencies(from: TargetNode,
                                        to: TargetNode,
                                        linkedStaticProducts: inout Set<StaticDepedencyWarning>) -> [LintingIssue] {
        guard to.target.product.isStatic, from.target.canLinkStaticProducts() else {
            return []
        }
        let warning = StaticDepedencyWarning(fromTargetNode: from,
                                             toTargetNode: to)
        let (inserted, oldMember) = linkedStaticProducts.insert(warning)
        guard inserted == false else {
            return []
        }

        let reason = "Target \(to.target.name) has been linked against \(oldMember.fromTargetNode.target.name) and \(from.target.name), it is a static product so may introduce unwanted side effects."
        let issue = LintingIssue(reason: reason, severity: .warning)
        return [issue]
    }

    private func lintMismatchingConfigurations(graph: Graphing) -> [LintingIssue] {
        let entryNodeProjects = graph.entryNodes.compactMap { $0 as? TargetNode }.map { $0.project }

        let knownConfigurations = entryNodeProjects.reduce(into: Set()) {
            $0.formUnion(Set($1.settings.configurations.keys))
        }

        let projectBuildConfigurations = graph.projects.map {
            (name: $0.name, buildConfigurations: Set($0.settings.configurations.keys))
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
    private func lintPackageDependencies(graph: Graphing) -> [LintingIssue] {
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
    private func lintCocoaPodsDependencies(graph: Graphing) -> [LintingIssue] {
        return graph.cocoapods.compactMap { node in
            let podfilePath = node.podfilePath
            if !FileHandler.shared.exists(podfilePath) {
                return LintingIssue(reason: "The Podfile at path \(podfilePath) referenced by some projects does not exist", severity: .error)
            }
            return nil
        }
    }

    private func lintCarthageDependencies(graph: Graphing) -> [LintingIssue] {
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

    struct LintableTarget: Equatable, Hashable {
        let platform: Platform
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
//            LintableTarget(platform: .iOS, product: .messagesExtension),
            LintableTarget(platform: .iOS, product: .stickerPackExtension),
//            LintableTarget(platform: .watchOS, product: .watch2App),
//            LintableTarget(platform: .watchOS, product: .watchApp),
        ],
        LintableTarget(platform: .iOS, product: .staticLibrary): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        LintableTarget(platform: .iOS, product: .staticFramework): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .iOS, product: .framework),
        ],
        LintableTarget(platform: .iOS, product: .dynamicLibrary): [
            LintableTarget(platform: .iOS, product: .dynamicLibrary),
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
//        LintableTarget(platform: .iOS, product: .messagesExtension): [
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
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
            LintableTarget(platform: .iOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .appExtension),
        ],
        LintableTarget(platform: .macOS, product: .staticLibrary): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .framework),
        ],
        LintableTarget(platform: .macOS, product: .staticFramework): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
            LintableTarget(platform: .macOS, product: .framework),
        ],
        LintableTarget(platform: .macOS, product: .dynamicLibrary): [
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
        ],
        LintableTarget(platform: .macOS, product: .framework): [
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .staticFramework),
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
            LintableTarget(platform: .iOS, product: .staticFramework),
//            LintableTarget(platform: .tvOS, product: .tvExtension),
        ],
        LintableTarget(platform: .tvOS, product: .staticLibrary): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .tvOS, product: .staticFramework): [
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .tvOS, product: .dynamicLibrary): [
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
        ],
        LintableTarget(platform: .tvOS, product: .framework): [
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .staticFramework),
        ],
        LintableTarget(platform: .tvOS, product: .unitTests): [
            LintableTarget(platform: .tvOS, product: .app),
            LintableTarget(platform: .tvOS, product: .staticLibrary),
            LintableTarget(platform: .tvOS, product: .dynamicLibrary),
            LintableTarget(platform: .tvOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
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
//        LintableTarget(platform: .watchOS, product: .watch2App): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//            LintableTarget(platform: .watchOS, product: .watch2Extension),
//        ],
//        LintableTarget(platform: .watchOS, product: .staticLibrary): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//        ],
//        LintableTarget(platform: .watchOS, product: .dynamicLibrary): [
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//        ],
//        LintableTarget(platform: .watchOS, product: .framework): [
//            LintableTarget(platform: .watchOS, product: .framework),
//        ],
//        LintableTarget(platform: .watchOS, product: .watchExtension): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//        ],
//        LintableTarget(platform: .watchOS, product: .watch2Extension): [
//            LintableTarget(platform: .watchOS, product: .staticLibrary),
//            LintableTarget(platform: .watchOS, product: .dynamicLibrary),
//            LintableTarget(platform: .watchOS, product: .framework),
//        ],
    ]
}
