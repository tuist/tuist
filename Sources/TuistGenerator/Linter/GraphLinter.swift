import Foundation
import TuistCore

protocol GraphLinting: AnyObject {
    func lint(graph: Graphing) -> [LintingIssue]
}

class GraphLinter: GraphLinting {
    // MARK: - Attributes

    let projectLinter: ProjectLinting
    let fileHandler: FileHandling

    // MARK: - Init

    init(projectLinter: ProjectLinting = ProjectLinter(),
         fileHandler: FileHandling = FileHandler()) {
        self.projectLinter = projectLinter
        self.fileHandler = fileHandler
    }

    struct StaticDepedencyWarning: Hashable {
        let fromTargetNode: TargetNode
        let toTargetNode: TargetNode

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

        return issues
    }

    private func lintCarthageDependencies(graph: Graphing) -> [LintingIssue] {
        let frameworks = graph.frameworks
        let carthageFrameworks = frameworks.filter { $0.isCarthage }
        let nonCarthageFrameworks = frameworks.filter { !$0.isCarthage }

        let carthageIssues = carthageFrameworks
            .filter { !fileHandler.exists($0.path) }
            .map { LintingIssue(reason: "Framework not found at path \($0.path.pathString). The path might be wrong or Carthage dependencies not fetched", severity: .warning) }
        let nonCarthageIssues = nonCarthageFrameworks
            .filter { !fileHandler.exists($0.path) }
            .map { LintingIssue(reason: "Framework not found at path \($0.path.pathString)", severity: .error) }

        var issues: [LintingIssue] = []
        issues.append(contentsOf: carthageIssues)
        issues.append(contentsOf: nonCarthageIssues)

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
            }
            issues.append(contentsOf: lintGraphNode(node: toNode,
                                                    evaluatedNodes: &evaluatedNodes,
                                                    linkedStaticProducts: &linkedStaticProducts))
        }

        return issues
    }

    private func lintDependency(from: TargetNode,
                                to: TargetNode,
                                linkedStaticProducts: inout Set<StaticDepedencyWarning>) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        var validLinks: [Bool] = []

        for fromPlatform in from.target.platform {
            let fromTarget = LintableTarget(platform: fromPlatform,
                                            product: from.target.product)

            if !GraphLinter.validLinks.keys.contains(fromTarget) {
                let reason = "Target \(from.target.name) has a platform '\(fromPlatform.caseValue)' and product '\(from.target.product)' invalid or not supported yet."
                let issue = LintingIssue(reason: reason, severity: .error)
                issues.append(issue)
            }

            for toPlatform in to.target.platform {
                let toTarget = LintableTarget(platform: toPlatform,
                                              product: to.target.product)

                let supportedTargets = GraphLinter.validLinks[fromTarget]!

                if supportedTargets.contains(toTarget) {
                    validLinks.append(true)
                } else {
                    validLinks.append(false)
                }
            }
        }

        if validLinks.contains(true) == false {
            let reason = "Target \(from.target.name) has a dependency with target \(to.target.name) of type \(to.target.product) for the platforms '\(to.target.platform.map(\.caseValue))' which is invalid or not supported yet."
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
//            LintableTarget(platform: .iOS, product: .appExtension),
//            LintableTarget(platform: .iOS, product: .messagesExtension),
//            LintableTarget(platform: .iOS, product: .stickerPack),
//            LintableTarget(platform: .watchOS, product: .watch2App),
//            LintableTarget(platform: .watchOS, product: .watchApp),
        ],
        LintableTarget(platform: .iOS, product: .staticLibrary): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .iOS, product: .staticFramework): [
            LintableTarget(platform: .iOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
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
        //        LintableTarget(platform: .iOS, product: .appExtension): [
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
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
//        LintableTarget(platform: .iOS, product: .stickerPack): [
//            LintableTarget(platform: .iOS, product: .staticLibrary),
//            LintableTarget(platform: .iOS, product: .dynamicLibrary),
//            LintableTarget(platform: .iOS, product: .framework),
//        ],
        // macOS
        LintableTarget(platform: .macOS, product: .app): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .macOS, product: .dynamicLibrary),
            LintableTarget(platform: .macOS, product: .framework),
            LintableTarget(platform: .iOS, product: .staticFramework),
//            LintableTarget(platform: .macOS, product: .appExtension),
        ],
        LintableTarget(platform: .macOS, product: .staticLibrary): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
        ],
        LintableTarget(platform: .macOS, product: .staticFramework): [
            LintableTarget(platform: .macOS, product: .staticLibrary),
            LintableTarget(platform: .iOS, product: .staticFramework),
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
        //        LintableTarget(platform: .macOS, product: .appExtension): [
//            LintableTarget(platform: .macOS, product: .staticLibrary),
//            LintableTarget(platform: .macOS, product: .dynamicLibrary),
//            LintableTarget(platform: .macOS, product: .framework),
//        ],
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
